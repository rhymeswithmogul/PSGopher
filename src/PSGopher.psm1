<#
PSGopher -- a PowerShell client for Gopher and Gopher+ servers.
Copyright (C) 2021-2022 Colin Cogle <colin@colincogle.name>

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License along
with this program.  If not, see <https://www.gnu.org/licenses/>.
#>

#Requires -Version 7.1
Function Invoke-GopherRequest {
	[CmdletBinding(DefaultParameterSetName='ToScreen')]
	[OutputType([PSCustomObject], ParameterSetName='ToScreen')]
	[OutputType([Void], ParameterSetName='OutFile')]
	[Alias('igr')]
	Param(
		[Parameter(Mandatory, Position=0)]
		[Alias('Url')]
		[ValidateNotNullOrEmpty()]
		[ValidatePattern('^gophers?:\/\/')]
		[Uri] $Uri,

		[Alias('UseTLS')]
		[Switch] $UseSSL,

		[Alias('Abstract','Admin','Attributes','Information')]
		[Switch] $Info,

		[ValidatePattern("[a-z]+\/.+")]
		[String[]] $Views,

		[ValidateSet('ASCII','UTF7','UTF8','UTF16','Unicode','UTF32')]
		[String] $Encoding = 'UTF8',

		[Parameter(ParameterSetName='OutFile')]
		[ValidateNotNullOrEmpty()]
		[String] $OutFile,

		[Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
		[Alias('Post','PostData','Query','QueryString')]
		[AllowNull()]
		[String] $InputObject
	)

	Set-StrictMode -Version Latest

	#region Establish TCP connection.
	# If we have the GopherS scheme, set UseSSL to true.
	$UseSSL = $UseSSL -or ($Uri.Scheme -eq 'gophers')
	
	# Sometimes, the .NET runtime doesn't recognize which port we're supposed
	# to be using -- especially if we use the non-standard "gophers" scheme for
	# a TLS connection.  If so, we need to make a new URL with the port defined.
	If ($Uri.Port -eq -1) {
		$Uri = [Uri]::new("$($Uri.Scheme)://$($Uri.Host):70$($Uri.PathAndQuery)")
		Write-Debug "New URL = $Uri"
	}

	Write-Verbose "Connecting to $($Uri.Host)$($UseSSL ? ' securely' : '')"
	Try {
		$TcpSocket = [Net.Sockets.TcpClient]::new($Uri.Host, $Uri.Port ?? 70)
		$TcpStream = $TcpSocket.GetStream()
		$TcpStream.ReadTimeout = 2000 #milliseconds
		If ($UseSSL) {
			Write-Debug 'Upgrading connection to TLS.'
			$secureStream = [Net.Security.SslStream]::new($TcpStream, $false)
			$secureStream.AuthenticateAsClient($Uri.Host)
			$TcpStream = $secureStream
		}
	}
	Catch {
		$msg = "Could not connect to $($Uri.Host):$($Uri.Port ?? 70)"
		If ($UseSSL) {
			$msg += ' with SSL/TLS'
		}
		$msg += '.  Aborting.'

		# Throw a non-terminating error so that $? is set properly and the
		# pipeline can continue.  This will allow chaining operators to work as
		# intended.  Should a future version of this module support pipeline
		# input, that will let this cmdlet keep running with other input URIs.
		$er = [Management.Automation.ErrorRecord]::new(
			[Net.WebException]::new($msg),
			'TlsConnectionFailed',
			[Management.Automation.ErrorCategory]::ConnectionError,
			$Uri
		)
		$er.CategoryInfo.Activity = 'NegotiateTlsConnection'
		$PSCmdlet.WriteError($er)
		Return $null
	}
	#endregion (Establish TCP connection)


	#region Content type negotiation
	$ContentTypeExpected = $null

	# If the user provided one, we'll use that.
	# But it needs to be removed from the URI.
	If ($Uri.AbsolutePath -CMatch "^\/[0123456789+gIT:;<dhis]") {
		$ContentTypeExpected = $Uri.AbsolutePath[1]

		# The code may have removed the leading slash.  Put that back.
		# If there was already one, remove it.
		$Path = $Uri.AbsolutePath.Substring(2)
		$Path = "/$Path" -Replace '//','/'

		Write-Debug "Stripped content type: was=$($Uri.AbsolutePath), now=$Path"

		$Uri = [Uri]::new("$($Uri.Scheme)://$($Uri.Host):$($Uri.Port)$Path")
	}

	# Otherwise, let's try and guess -- if we have a file extension.
	ElseIf ($Uri.AbsolutePath -Match '\.') {
		$ContentTypeExpected = (Get-GopherType ($Uri.AbsolutePath -Split '\.')[-1] -Verbose:$VerbosePreference -Debug:$DebugPreference)
	}

	# If we still can't figure it out after all this, assume it's a Gopher menu.
	$ContentTypeExpected ??= 1

	# Determine if we're reading a binary file or text.
	$BINARY_TRANSFER = (-Not $Info) -and ($ContentTypeExpected -In @(4,5 ,9,'g','I',':',';','<','d','s') )
	#endregion (Content type negotiation)

	#region Parse input parameters
	If ($null -eq $InputObject -or $InputObject.Length -eq 0) {
		Write-Debug 'No query string detected.'
	}
	Else {
		Write-Debug "Found query string=$InputObject"

		$Encoder = [Web.HttpUtility]::ParseQueryString('')
		$Encoder.Add($null, $InputObject)
		$EncodedInput = $Encoder.ToString() -Replace '\+','%20'	# Gopher requires URL (percent) encoding for spaces.
		
		Write-Debug "Encoded query string=$EncodedInput"

		$Uri = [Uri]::new($Uri.ToString() + '?' + $EncodedInput)
	}
	#endregion

	#region Send request
	$ToSend = $Uri.AbsolutePath
	If ($Info) {
		If ($ContentTypeExpected -eq 1) {
			$ToSend += "`t$"
		}
		Else {
			$ToSend += "`t!"
		}
	}
	If ($Views) {
		$ToSend += "`t+$Views"
	}
	$ToSend += "`r`n"
	Write-Debug "Sending $($ToSend.Length) bytes to server:  $($ToSend -Replace "`r",'\r' -Replace "`n",'\n' -Replace "`t",'\t')"
	$writer = [IO.StreamWriter]::new($TcpStream)
	$writer.WriteLine($ToSend)
	$writer.Flush()
	#endregion (Send request)

	#region Receive data
	# Set text encoding for reading and writing textual output.
	If (-Not $BINARY_TRANSFER) {
		Switch ($Encoding) {
			'ASCII'   {$Encoder = [Text.AsciiEncoding]::new()}
			'UTF7'    {$Encoder = [Text.UTF7Encoding]::new()}
			'UTF8'    {$Encoder = [Text.UTF8Encoding]::new()}
			'UTF16'   {$Encoder = [Text.UnicodeEncoding]::new()}
			'Unicode' {$Encoder = [Text.UnicodeEncoding]::new()}
			'UTF32'   {$Encoder = [Text.UTF32Encoding]::new()}
			default   {Throw [NotImplementedException]::new('An unknown Encoder was specified.')}
		}
	}

	# Read the full response.
	$response = ($BINARY_TRANSFER ? [IO.MemoryStream]::new() : '')
	$BufferSize = 102400 	# 100 KB, more than enough for text, but a sizable
							# buffer to make binary transfers fast.
	$buffer = New-Object Byte[] $BufferSize

	If (-Not $BINARY_TRANSFER)
	{
		If ($Info) {
			Write-Debug "Beginning to read (attributes)."
		} Else {
			Write-Debug "Beginning to read (textual type $ContentTypeExpected)."
		}
		
		While (0 -ne ($bytesRead = $TcpStream.Read($buffer, 0, $BufferSize))) {
			Write-Debug "`tReading ≤$BufferSize bytes from the server."
			$response += $Encoder.GetString($buffer, 0, $bytesRead)
		}
		Write-Verbose "Received $($Encoder.GetByteCount($response)) bytes from server."
	}
	Else # it is a binary transfer #
	{
		Write-Debug "Beginning to read (binary type $ContentTypeExpected)."
		While (0 -ne ($bytesRead = $TcpStream.Read($buffer, 0, $BufferSize))) {
			Write-Debug "`tRead ≤$BufferSize bytes from the server."
			$response.Write($buffer, 0, $bytesRead)
		}
		$response.Flush()
		Write-Verbose "Received $($response.Length) bytes from server."
	}
	#endregion (Receive data)

	# Close connections.
	Write-Debug 'Closing connections.'
	$writer.Close()
	$TcpSocket.Close()

	#region Parse response
	$Content = ''
	$Links = @()

	# Check for errors.  All errors begin with '3'.
	If ( `
		($BINARY_TRANSFER -and $response.ToArray()[0] -eq 51) -or `
		(-Not $BINARY_TRANSFER -and $response[0] -eq '3' -and $response -CLike '*error.host*') `
	) {
		If ($BINARY_TRANSFER) {
			$response = [Text.Encoding]::ASCII.GetString($response.ToArray())
		}
		Write-Error -Message ($response.Substring(1, $response.IndexOf("`t"))) -TargetObject $Uri -ErrorId 3 -Category 'ResourceUnavailable'
		Return $null
	}
	# If this is not a Gopher menu, then simply return the raw output.
	ElseIf ($BINARY_TRANSFER) {
		$Content = $response.ToArray()
	}
	# If this is anything non-binary and not a menu, simply return it.
	ElseIf ($ContentTypeExpected -ne 1) {
		$Content = $response
	}
	Else {
		$response -Split "(`r`n)" | ForEach-Object {
			Write-Debug "OUTPUT: $($_ -Replace "`r",'' -Replace "`n",'')"

			# Build Content variable
			If ($_.Length -gt 0) {
				$Content += ($_.Substring(1) -Split "`t")[0]
			}
			Else {
				$Content += "`r`n"
			}

			# Look for links or errors.  However, we can skip this if we're using
			# the -OutFile or -Info parameters, because no link objects are returned.
			If (-Not $OutFile -and -Not $Info  -and $_ -Match "`t") {
				$line = $_
				Switch -RegEx ($_[0]) {
					'i' {
						Break
					}

					default {
						$result = Convert-GopherLink $line -Server $Uri.Host -Port $Uri.Port -Verbose:$VerbosePreference -Debug:$DebugPreference
						$Links += $result
					}
				}
			}
		}
	}
	#endregion (Parse response)

	#region Generate output
	# If we are saving the output to a file, then we do not send anything to the
	# output buffer.  We save the Content to a file instead.
	If ($OutFile) {
		# Don't write output if an error occurred.
		If ($response[0] -eq '3') {
			Write-Error $Content
			Return $null
		} Else {
			If (-Not $BINARY_TRANSFER)
			{
				Write-Verbose "Writing $($Encoder.GetByteCount($response)) bytes to $OutFile"
				Set-Content -Path $OutFile -Value $Content -Encoding $Encoding 
			}
			Else {
				Write-Verbose "Writing $($response.Length) bytes to $OutFile"
				Set-Content -Path $OutFile -Value $Content -AsByteStream 
			}
		}
		Return
	}
	# TODO: figure out how to parse Gophermaps in Gopher+ mode.
	# For now, let's skip all this and return it as plain text.
	ElseIf ($Info -and $ContentTypeExpected -ne 1) {
		$Result = [PSCustomObject]@{}

		# For each line of Gopher+ output, we're going to see if it begins with
		# a plus sign.  If so, we have an attribute name.  Then, we're going to
		# go through each line of output and save that.  Once we find another
		# attribute name, add the two items to $Result.
		$AttributeName = ''
		$AttributeValue = ''
		$response -Split "(\+[A-Z]+):" | ForEach-Object {
			If ($_.Length -gt 0) {
				Write-Debug "Gopher+ output line: $_"
				# If we've found an attribute, then add the current name/value
				# into $Result (if there is one).
				If ($_[0] -eq '+') {
					If ($AttributeValue) {
						If ($AttributeName -In @('ADMIN', 'VIEWS')) {
							$splits = $AttributeValue.Split("`r`n", [StringSplitOptions]::RemoveEmptyEntries).Trim()
							$Result | Add-Member -NotePropertyName $AttributeName -NotePropertyValue $splits
							# ($AttributeValue -Split "\s*\r\n\s*")
						}
						Else {
							$Result | Add-Member -NotePropertyName $AttributeName -NotePropertyValue $AttributeValue.Trim()
						}
					}

					# Now, get ready for the next attribute.
					$AttributeName  = $_.Substring(1).Trim()
					$AttributeValue = ''
				}
				# This is not an attribute name, so add it to our
				# currently-saved value.
				Else {
					$AttributeValue += $_
				}
			}
		}

		# What's left in $AttributeValue must be an attribute.
		# This is a repeat of the above few lines of code.  If anyone can
		# refactor this into something better, please do!
		If ($AttributeName -In @('ADMIN', 'VIEWS')) {
			$Result | Add-Member -NotePropertyName $AttributeName -NotePropertyValue $AttributeValue.Split("\s*(\r\n)+\s*", [StringSplitOptions]::RemoveEmptyEntries)
		}
		Else {
			$Result | Add-Member -NotePropertyName $AttributeName -NotePropertyValue $AttributeValue.Trim()
		}
		Return $Result
	}
	Else {
		# Let's tell the user how we fetched this resource/attributes.
		# This will be more useful when I implement opportunistic TLS.
		$Protocol = ($Info -or $Views ? 'Gopher+' : 'Gopher')
		$Protocol = ($UseSSL          ? "Secure$Protocol" : $Protocol)

		Return [PSCustomObject]@{
			'Protocol' = $Protocol
			'ContentType' = $ContentTypeExpected ?? 1
			'Content' = $Content
			'Encoding' = ($BINARY_TRANSFER ? $Content.GetType() : $Encoder.GetType())
			'Images'  = $Links | Where-Object Type -In @('g','I')
			'Links' = $Links
			'RawContent'  = ($BINARY_TRANSFER ? $response.ToArray() : $response)
			'RawContentLength' = $response.Length
		}
	}
	#endregion (Generate output)
}

Function Convert-GopherLink {
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
	Param(
		[Parameter(Mandatory, Position=0)]
		[ValidateNotNullOrEmpty()]
		[ValidatePattern('^(?:.)(?:[^\t]*)\t')]
		[String] $InputObject,

		[String] $Server,

		[UInt16] $Port
	)

	Write-Debug '*** Found a Gopher link.'
	$fields = $InputObject -Split "`t"
	$Uri    = $null

	# Are we dealing with a /URL: link?  If so, we can easily create
	# the href [Uri].  Otherwise, we'll need to build it ourselves.
	If ($fields[1] -CLike 'URL:*' -or $fields[1] -CLike '/URL:*') {
		$Uri = [Uri]::new($fields[1] -Replace [RegEx]"\/?URL:",'')
	}
	Else {
		$Server = ${fields}?[2] ?? $Server
		$Port   = ${fields}?[3] ?? $Port

		# Pick the appropriate URL schema for the link type.
		# For the first two (CCSO and Telnet), there should be nothing after the
		# optional port, but let's include it anyway.
		Switch -RegEx ($fields[0][0]) {
			'2'     {$Port ??= 105; $Uri = [Uri]::new("cso://${Server}:$Port/$($fields[1])")}
			'[8T]'  {$Port ??= 23;  $Uri = [Uri]::new("telnet://${Server}:$Port/$($fields[1])")}
			default {$Port ??= 70;  $Uri = [Uri]::new("gopher://${Server}:$Port/$($fields[1])")}
		}
	}

	Write-Debug "*** Type=$($fields[0][0]): $Uri"
	Write-Verbose "LINK: Type=$($fields[0][0]): $Uri"
	Return [PSCustomObject]@{
		'href' = $uri
		'Type' = $fields[0][0]
		'Description' = $fields[0].Substring(1)
		'Resource' = $Uri.AbsolutePath
		'Server' = $Uri.Host
		'Port' = $Uri.Port
		'UrlLink' = ($InputObject -Match '\t\/?URL:')
	}
}

# This helper function guessed at types when the user forgets to enter one.
# This ensures that data will be returned in either text or binary format.
# Feel free to add extensions and types as you see fit.
Function Get-GopherType {
	[CmdletBinding()]
	[OutputType([Char])]
	Param(
		[ValidateNotNullOrEmpty()]
		[String] $Extension
	)

	# This list will be searched case-insensitively.
	$Extensions = @{
		'ace' = 9				# ACE archive
		'ai' = 'I'				# Adobe Illustrator image
		'aif[cf]?' = '<'		# AIFF sound
		'applescript|scpt' = 0	# AppleScript code
		'arj' = 9				# ARJ archive
		'art' = 'I'				# AOL ART image
		'asc' = 0				# GPG data (text)
		'asf' = ';'				# ASF sound
		'asm|s' = 0				# Assembly code
		'ass|ssa|srt' = 0		# Subtitles
		'au' = '<'				# Sound
		'av1' = ';'				# AV1 movie
		'avi' = ';'				# AVI movie
		'avif' = 'I'			# AVIF image
		'bat|cmd' = 0			# Batch file
		'bin' = 9				# Generic binary
		'bmp|dib|pcx' = ':'		# Bitmap image
		'br' = 9				# Brotli-compressed data
		'bz2' = 9				# BZIP2 archive
		'c|h' = 0				# C source code
		'cab' = 9				# Windows cabinet	
		'cer' = 0				# Certificate (probably text)
		'cgm' = 'I'				# CGM image
		'coffee' = 0			# CoffeeScript
		'conf|cfg?|ini' = 0		# Config file
		'cpio' = 9				# CPIO archive
		'[ch](?:pp|xx)' = 0		# C++ code	
		'crl' = 9				# Certificate revocation list
		'crt' = 9				# Certificate (probably binary)
		'[ch]s' = 0				# C# code
		'css' = 0				# CSS stylesheet
		'csv' = 0				# CSV data
		'cur|ani' = 5			# Windows cursor
		'deb|rpm|apk' = 9		# Linux packages
		'der' = 0				# Certificate (as text)
		'diff' = 0				# diff
		'dll' = 5				# DOS/Windows library
		'dmg|sparseimage' = 9	# macOS disk image
		'dng' = 'I'				# Digital negative
		'dns' = 0				# DNS zone
		'do[ct][mx]?' = 'd'		# Microsoft Word document
		'dsk' = 9				# Disk image
		'dvi' = 'd'				# DVI document
		'dvr-ms' = ';'			# Windows Media Center movie
		'dwg' = 'I'				# AutoCAD image
		'ebuild' = 0			# Gentoo ebuild
		'emf|wmf' = 'I'			# Windows metafile image
		'eml|msg' = 0			# Email message
		'eps' = 'I'				# Vector image
		'epub|mobi' = 9			# Book
		'exe|com|pif' = 5		# DOS/Windows app
		'f?odg|otg' = 'I'		# OpenDocument drawing
		'f?odp|otp' = 'd'		# OpenDocument presentation
		'f?ods|ots' = 'd'		# OpenDocument spreadsheet
		'f?odt|ott' = 'd'		# OpenDocument document
		'fon' = 5				# DOS/Windows font
		'flac' = '<'			# FLAC audio
		'flv' = ';'				# Flash video
		'gif' = 'g'				# GIF image
		'gifv' = ';'			# GIFV video
		'gmi' = 0				# Gemtext
		'gnumeric' = 'd'		# Gnumeric spreadsheet
		'go' = 0				# Go source code
		'gpg' = 9				# GPG data (binary)
		'gz' = 9				# Compressed data
		'hei[cf]' = 'I'			# HEIC image
		'hqx' = 4				# BinHex archive
		'html?' = 'h'			# HTML document
		'icns' = 'I'			# macOS icon
		'ico' = 'I'				# Windows icon
		'img' = 9				# Disk image
		'inf' = 0				# Windows INF file
		'ini' = 0				# Configuration file
		'ipsw' = 9				# iOS/iPod software update
		'iso' = 9				# CD image
		'jar' = 9				# Java app
		'java' = 0				# Java source code
		'jp2' = 'I'				# JPEG 2000 image
		'jpe?g' = 'I'			# JPEG image
		'js' = 0				# JavaScript code
		'json' = 0				# JSON data
		'jsonld' = 0			# JSON-LD data
		'jxl' = 'I'				# JPEG XL image
		'lnk' = 5				# Windows shortcut
		'log' = 0				# Log
		'lua' = 0				# Lua source code
		'lz' = 9				# Compressed data
		'lzh' = 9				# Compressed data
		'lzma' = 9				# Compressed data
		'lzo' = 9				# Compressed data
		'm3u8?' = '<'			# Playlist
		'm4' = 0				# M4 source code
		'm4[abpr]' = '<'		# MPEG-4 audio formats (mostly iTunes)
		'm4v|mp4' = ';'			# MPEG-4 container (usually video)
		'md|markdown' = 0		# Markdown text
		'midi?' = '<'			# MIDI music
		'mkv' = ';'				# Matroska video
		'mov' = ';'				# QuickTime movie
		'mp3' = '<'				# MP3 audio
		'mpe?g' = ';'			# MPEG movie
		'mpp' = 'd'				# Microsoft Project document
		'msp' = 'I'				# Microsoft Paintbrush image
		'numbers' = 'd'			# Numbers spreadsheet
		'o' = 9					# Object file
		'ocx' = 5				# ActiveX control
		'odb' = 'd'				# OpenDoucment database
		'odf' = 'd'				# OpenDocument formula
		'og[gm]' = '<'			# Ogg audio
		'ogv' = ';'				# Ogg video
		'ovl' = 5				# DOS overlay
		'o?xps' = 'd'			# (Open)XPS document
		'pages' = 'd'			# Pages document
		'par2?' = 9				# PAR archive
		'pas' = 0				# Pascal code
		'pbm' = ':'				# PBM image
		'pi?ct' = 'I'			# Apple PICT image
		'pdf' = 'd'				# PDF document
		'pdn' = 'I'				# Paint.NET image
		'pem' = 0				# PEM-encoded data
		'pfx|p12|p7[bc]' = 9	# Certificates
		'php[345]?' = 0			# PHP code
		'pl' = 0				# Perl code
		'png' = 'I'				# PNG image
		'pptx?|pps|pot' = 'd'	# PowerPoint presentation
		'ps' = 'd'				# PostScript document
		'psd' = 'I'				# Photoshop image
		'psp' = 'I'				# Paint Shop Pro image
		'ps[cdm]?1|ps1xml' = 0	# PowerShell code
		'pub' = 'd'				# Publisher document
		'py' = 0				# Python code
		'py[co]' = 9			# Python bytecode
		'r' = 0					# R code
		'rar' = 9				# WinRAR archive
		'rb' = 0				# Ruby source code
		'rdp' = 0				# Microsoft Remote Desktop connection
		'rss|atom' = 0			# News feed
		'rtfd?' = 'd'			# Rich Text Format document
		'scr' = 5				# Windows screen saver
		'scss' = 0				# Sass code
		'sh|bash|command' = 0	# Shell script
		'sht(?:ml)?' = 'h'		# HTML with includes
		'sitx?' = 9				# Stuffit archive
		'snd' = '<'				# Sound
		'sql' = 0				# SQL code
		'svgz?' = 'I'			# SVG image
		'sys|drv' = 5			# DOS/Windows driver
		'tab|tsv' = 'd'			# Tab-encoded values
		'tar' = 9				# TAR archive
		'targa|tga' = 'I'		# Targa image
		'tcl' = 0				# TCL code
		'tex' = 0				# Tex code
		'tiff?' = 'I'			# TIFF image
		'tt[cf]|otf|woff2?' = 9	# Font
		'txt' = 0				# Text
		'uue' = 6				# UUEncoded data
		'vbs' = 0				# VBScript
		'vhdx?' = 9				# Windows disk image
		'vsdx?' = 'I'			# Visio drawing
		'wav' = '<'				# Wave audio
		'webm' = ';'			# WebM video
		'webp|wp2' = 'I'		# WebP (2) image
		'wim|esd' = 9			# Windows Image (archive)
		'wma|asf' = ';'			# Windows Media audio
		'wmf|emf' = 'I'			# Windows Metafile image
		'wmv' = ';'				# Windows Media video
		'wpt?' = 'd'			# WordPerfect doucment
		'wri' = 'd'				# Windows Write document
		'xcf' = 'I'				# GIMP image
		'xht(?:ml)?' = 'h'		# XHTML code
		'xl(s[bmx]?|w)' = 'd'	# Excel document
		'xltm?'	= 'd'			# Excel template
		'xml|rdf' = 0			# XML code
		'xpm' = 'I'				# XPM image
		'xsd' = 0				# XSD code
		'xslt?' = 0				# XML stylesheet
		'xz' = 9				# Compressed data
		'ya?ml' = 0				# YAML code
		'Z' = 9					# Compressed data
		'zip' = 9				# Zip archive
		'zoo' = 9				# ZOO archive
		'123' = 'd'				# Lotus 1-2-3 document
		'7z' = 9				# 7-zip archive
	}

	$Result = $null
	ForEach ($regex in $Extensions.GetEnumerator()) {
		Write-Debug "Testing extension $Extension against $($regex.Name)."
		If ($Extension -Match $regex.Name) {
			$Result = $regex.Value
			Break
		}
	}
	Write-Verbose "Guessing that the extension $Extension is of type $($Result ?? 'unknown')."
	Return $Result
}
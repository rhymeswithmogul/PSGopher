﻿<#
PSGopher -- a PowerShell client for Gopher and Gopher+ servers.
Copyright (C) 2021-2023 Colin Cogle <colin@colincogle.name>

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
		[ValidatePattern('^(gophers?|sgopher|gopher\+tls):\/\/')]
		[Uri] $Uri,

		[Alias('UseTLS', 'RequireTLS', 'RequireSSL')]
		[Switch] $UseSSL,

		[Alias('TryTLS', 'OpportunisticTLS', 'OpportunisticSSL')]
		[Switch] $TrySSL,

		[Alias('Abstract','Admin','Attributes','Information')]
		[Switch] $Info,

		[ValidatePattern("[a-z]+\/.+")]
		[AllowNull()]
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

	#region Establish TCP connection.
	# If we have a secure URL scheme, set UseSSL to true.
	$UseSSL = $UseSSL -or ($Uri.Scheme -In @('gophers','sgopher','gopher+tls'))

	# Sometimes, the .NET runtime doesn't recognize which port we're supposed
	# to be using -- especially if we use a Gopher-TLS scheme for a secure
	# connection.  If so, we need to make a new URL with the port defined.
	If ($Uri.Port -eq -1) {
		$Path, $Query = $Uri.PathAndQuery -Split '\?',2
		$Uri = [Uri]::new("$($Uri.Scheme)://$($Uri.Host):70$Path$($Query ? "?$Query" : '')")
		# New URL = ___
		Write-Debug (Get-MessageTranslation 1 $Uri)
	}

	If ($UseSSL -ne $true) {
		# "Connecting to ___."
		Write-Verbose (Get-MessageTranslation 2 $Uri.Host)
	}
	Else {
		# "Connecting to ___ securely."
		Write-Verbose (Get-MessageTranslation 3 $Uri.Host)
	}

	Try {
		$TcpSocket = [Net.Sockets.TcpClient]::new($Uri.Host, $Uri.Port ?? 70)
		$TcpStream = $TcpSocket.GetStream()
		$TcpStream.ReadTimeout = 2000 #milliseconds
		If ($UseSSL -or $TrySSL) {
			# "Upgrading connection to TLS."
			Write-Debug (Get-MessageTranslation 4)
			$secureStream = [Net.Security.SslStream]::new($TcpStream, $false)
			$secureStream.AuthenticateAsClient($Uri.Host)
			$TcpStream = $secureStream
			# Connected with <TLS version> using <cipher/ciphersuite>".
			Write-Debug (Get-MessageTranslation 5 @($TcpStream.SslProtocol, $TcpStream.NegotiatedCipherSuite))
		}
	}
	Catch {
		# If we're using -TrySSL, then we'll retry without encryption.  Else,s
		# If we're using -UseSSL, then fail the connection.
		If ($UseSSL) {
			# Throw a non-terminating error so that $? is set properly and the
			# pipeline can continue.  This will allow chaining operators to work as
			# intended.  Should a future version of this module support pipeline
			# input, that will let this cmdlet keep running with other input URIs.
			$er = [Management.Automation.ErrorRecord]::new(
				# "Could not connect to {host}:{port} with SSL/TLS.  Aborting."
				[Net.WebException]::new((Get-MessageTranslation 7 @($Uri.Host, $Uri.Port ?? 70))),
				'TlsConnectionFailed',
				[Management.Automation.ErrorCategory]::ConnectionError,
				$Uri
			)
			$er.CategoryInfo.Activity = 'NegotiateTlsConnection'
			$PSCmdlet.WriteError($er)
			Return $null
		}
		ElseIf ($TrySSL) {
			# "Could not connect to {host}:{port} with SSL/TLS.  Retrying with a non-secured connection."
			Write-Verbose (Get-MessageTranslation 8 @($Uri.Host, $Uri.Port ?? 70))
			$NewParameters = @{
				'Uri' = $Uri
				'Info' = $Info
				'Views' = $Views ?? @()	# not sure why this is needed
				'Encoding' = $Encoding
				'InputObject' = $InputObject
				'TrySSL' = $null
				'UseSSL' = $null
			}

			If ($PSCmdlet.ParameterSetName -eq 'OutFile') {
				$NewParameters.'OutFile' = $OutFile
			}

			Remove-Variable -Name 'SecureStream' -Force
			Return (Invoke-GopherRequest @NewParameters)
			Exit
		}
		Else {
			# "Could not connect to {host}:{port}.  Aborting."
			Write-Error (Get-MessageTranslation 6 @($Uri.Host, $Uri.Port ?? 70))
			Return $null
		}
	}
	#endregion (Establish TCP connection)


	#region Content type negotiation
	$ContentTypeExpected = $null

	# If the user provided one, we'll use that.
	# But it needs to be removed from the URI.
	If ($Uri.PathAndQuery -CMatch "^\/[0123456789+gIT:;<dhis]") {
		$ContentTypeExpected = $Uri.PathAndQuery[1]

		# The code may have removed the leading slash.  Put that back.
		# If there was already one, remove it.
		$Path = $Uri.PathAndQuery.Substring(2)
		$Path = "/$Path" -Replace '//','/'

		Write-Debug (Get-MessageTranslation 9 @($Uri.PathAndQuery, $Path))

		$Uri = [Uri]::new("$($Uri.Scheme)://$($Uri.Host):$($Uri.Port)$Path")
	}

	# Otherwise, let's try and guess -- if we have a file extension.
	ElseIf ($Uri.AbsolutePath -Match '\.') {
		$ContentTypeExpected = (Get-GopherType ($Uri.AbsolutePath -Split '\.')[-1] -Verbose:$VerbosePreference -Debug:$DebugPreference)
	}

	# If we still can't figure it out after all this, assume it's a Gopher menu.
	$ContentTypeExpected ??= '1'

	# Determine if we're reading a binary file or text.
	$BINARY_TRANSFER = (-Not $Info) -and ($ContentTypeExpected -In @('4','5','9','g','I',':',';','<','d','s') )
	#endregion (Content type negotiation)

	#region Parse input parameters
	If ($null -eq $InputObject -or $InputObject.Length -eq 0) {
		# "No additional query string detected"
		Write-Debug (Get-MessageTranslation 10)
	}
	Else {
		# "Found additional query string=___"
		Write-Debug (Get-MessageTranslation 11 $InputObject)

		$Encoder = [Web.HttpUtility]::ParseQueryString('')
		$Encoder.Add($null, $InputObject)
		$EncodedInput = $Encoder.ToString() -Replace '\+','%20'	# Gopher requires URL (percent) encoding for spaces.

		# "Encoded additional query string=___"
		Write-Debug (Get-MessageTranslation 12 $EncodedInput)

		# If there was already a query string specified in the URL, we will send
		# both of them, with the URL taking precedence.
		If ($Uri.Query) {
			# "Found existing query string=___"
			Write-Debug (Get-MessageTranslation 13 $Uri.Query)
		}
		$Uri = [Uri]::new($Uri.ToString() + ($Uri.Query ? '&' : '?') + $EncodedInput)
	}
	#endregion

	#region Send request
	$ToSend = $Uri.PathAndQuery
	If ($Info) {
		If ($ContentTypeExpected -eq '1') {
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
	# "Sending ___ bytes to server: ___"
	Write-Debug (Get-MessageTranslation 14 @($ToSend.Length, ($ToSend -Replace "`r",'\r' -Replace "`n",'\n' -Replace "`t",'\t')))
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
			default   {Throw [NotImplementedException]::new((Get-MessageTranslation 15))}
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
			# "Beginning to read (attributes)"
			Write-Debug (Get-MessageTranslation 16)
		} Else {
			# "Beginning to read (textual type ___)"
			Write-Debug (Get-MessageTranslation 17 $ContentTypeExpected)
		}

		While (0 -ne ($bytesRead = $TcpStream.Read($buffer, 0, $BufferSize))) {
			# <TAB> "Reading ≤___ bytes from the server."
			Write-Debug "`t$(Get-MessageTranslation 18 $BufferSize)"
			$response += $Encoder.GetString($buffer, 0, $bytesRead)
		}
		# "Received ___ bytes from server."
		Write-Verbose (Get-MessageTranslation 19 $Encoder.GetByteCount($response))
	}
	Else # it is a binary transfer #
	{
		# "Beginning to read (binary type ___)."
		Write-Debug (Get-MessageTranslation 20 $ContentTypeExpected)
		While (0 -ne ($bytesRead = $TcpStream.Read($buffer, 0, $BufferSize))) {
			# <TAB> "Reading ≤___ bytes from the server."
			Write-Debug "`t$(Get-MessageTranslation 18 $BufferSize)"
			Write-Debug "`tGot $bytesRead bytes"
			$response.Write($buffer, 0, $bytesRead)
		}
		$response.Flush()
		# "Received ___ bytes from server."
		Write-Verbose (Get-MessageTranslation 19 $response.Length)
	}
	#endregion (Receive data)

	# Close connections.
	Write-Debug (Get-MessageTranslation 21)
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
		If (-Not $Views) {
			$Content = $response.ToArray()
		}
		Else {
			# A Views query will include a plus sign, the file size, and then a
			# \r\n.  Remove that header from the Content.
			$arr = $response.ToArray()
			$dataStarts = 0
			If ($arr[0] -eq 43) <# a plus sign #>
			{
				For ($i = 0; $i -lt $arr.Length; $i++) {
					If ($arr[$i] -eq 13 -and $arr[$i + 1] -eq 10) {
						$dataStarts = $i + 2
						Break
					}
				}
			}

			$Content = $arr[$dataStarts..($arr.Length)]
		}
	}
	# If this is anything non-binary and not a menu, simply return it.
	ElseIf ($ContentTypeExpected -ne '1') {
		If (-Not $Views) {
			$Content = $response
		}
		Else {
			$Content = ($response -Split "`r`n",2)[1]
		}
	}
	Else {
		$response -Split "(`r`n)" | ForEach-Object {
			# Show the output
			Write-Debug (Get-MessageTranslation 22 ($_ -Replace "`r",'' -Replace "`n",''))

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
				Switch -CaseSensitive -RegEx ($_[0]) {
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
				# "Writing # bytes to <filename>"
				Write-Verbose (Get-MessageTranslation 23 @($Encoder.GetByteCount($response), $OutFile))
				Set-Content -Path $OutFile -Value $Content -Encoding $Encoding -NoNewline
			}
			Else {
				# "Writing # bytes to <filename>"
				Write-Verbose (Get-MessageTranslation 23 @($response.Length, $OutFile))
				Set-Content -Path $OutFile -Value $Content -AsByteStream
			}
		}
		Return
	}
	# TODO: figure out how to parse Gophermaps in Gopher+ mode.
	# For now, let's skip all this and return it as plain text.
	ElseIf ($Info -and $ContentTypeExpected -ne '1') {
		$Result = [PSCustomObject]@{}

		# For each line of Gopher+ output, we're going to see if it begins with
		# a plus sign.  If so, we have an attribute name.  Then, we're going to
		# go through each line of output and save that.  Once we find another
		# attribute name, add the two items to $Result.
		$AttributeName = ''
		$AttributeValue = ''
		$response -Split "(\+[A-Z]+):" | ForEach-Object {
			If ($_.Length -gt 0) {
				# "Gopher+ output line: ___"
				Write-Debug (Get-MessageTranslation 24 $_)
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
		$Protocol = 'Gopher'
		If ($Info -or $Views) {
			$Protocol = 'Gopher+'
		}
		If ((Test-Path 'variable:\SecureStream') -and ($null -ne $SecureStream)) {
			$Protocol = "Secure$Protocol"
		}

		Return [PSCustomObject]@{
			'Protocol' = $Protocol
			'ContentType' = $ContentTypeExpected ?? '1'
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

	# "*** Found a Gopher link."
	Write-Debug "*** $(Get-MessageTranslation 25)"
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
		Switch -CaseSensitive -RegEx ($fields[0][0]) {
			'2'     {$Port ??= 105; $Uri = [Uri]::new("cso://${Server}:$Port/$($fields[1])")}
			'[8T]'  {$Port ??= 23;  $Uri = [Uri]::new("telnet://${Server}:$Port/$($fields[1])")}
			default {$Port ??= 70;  $Uri = [Uri]::new("gopher://${Server}:$Port/$($fields[1])")}
		}
	}

	# "*** Type=_: <URL>" and "LINK: Type=_: <URL>", respectively.
	Write-Debug   "*** $(Get-MessageTranslation 26 @($fields[0][0], $Uri))"
	Write-Verbose "*** $(Get-MessageTranslation 27 @($fields[0][0], $Uri))"
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
		'ace' = '9'				# ACE archive
		'ai' = 'I'				# Adobe Illustrator image
		'aif[cf]?' = '<'		# AIFF sound
		'applescript|scpt' = '0'# AppleScript code
		'arj' = '9'				# ARJ archive
		'art' = 'I'				# AOL ART image
		'asc' = '0'				# GPG data (text)
		'asf' = ';'				# ASF sound
		'asm|s' = '0'			# Assembly code
		'ass|ssa|srt' = '0'		# Subtitles
		'au' = '<'				# Sound
		'av1' = ';'				# AV1 movie
		'avi' = ';'				# AVI movie
		'avif' = 'I'			# AVIF image
		'bat|cmd' = '0'			# Batch file
		'bin' = '9'				# Generic binary
		'bmp|dib|pcx' = ':'		# Bitmap image
		'br' = '9'				# Brotli-compressed data
		'bz2' = '9'				# BZIP2 archive
		'c|h' = '0'				# C source code
		'cab' = '9'				# Windows cabinet
		'cer' = '0'				# Certificate (probably text)
		'cgm' = 'I'				# CGM image
		'coffee' = '0'			# CoffeeScript
		'conf|cfg?|ini' = '0'	# Config file
		'cpio' = '9'			# CPIO archive
		'[ch](?:pp|xx)' = '0'	# C++ code
		'crl' = '9'				# Certificate revocation list
		'crt' = '9'				# Certificate (probably binary)
		'[ch]s' = '0'			# C# code
		'css' = '0'				# CSS stylesheet
		'csv' = '0'				# CSV data
		'cur|ani' = '5'			# Windows cursor
		'deb|rpm|apk' = '9'		# Linux packages
		'der' = '0'				# Certificate (as text)
		'diff' = '0'			# diff
		'dll' = '5'				# DOS/Windows library
		'dmg|sparseimage' = '9'	# macOS disk image
		'dng' = 'I'				# Digital negative
		'dns' = '0'				# DNS zone
		'do[ct][mx]?' = 'd'		# Microsoft Word document
		'dsk' = '9'				# Disk image
		'dvi' = 'd'				# DVI document
		'dvr-ms' = ';'			# Windows Media Center movie
		'dwg' = 'I'				# AutoCAD image
		'ebuild' = '0'			# Gentoo ebuild
		'emf|wmf' = 'I'			# Windows metafile image
		'eml|msg' = '0'			# Email message
		'eps' = 'I'				# Vector image
		'epub|mobi' = '9'		# Book
		'exe|com|pif' = '5'		# DOS/Windows app
		'f?odg|otg' = 'I'		# OpenDocument drawing
		'f?odp|otp' = 'd'		# OpenDocument presentation
		'f?ods|ots' = 'd'		# OpenDocument spreadsheet
		'f?odt|ott' = 'd'		# OpenDocument document
		'fon|fot' = '5'			# DOS/Windows font
		'flac' = '<'			# FLAC audio
		'flv' = ';'				# Flash video
		'gif' = 'g'				# GIF image
		'gifv' = ';'			# GIFV video
		'gmi' = '0'				# Gemtext
		'gnumeric' = 'd'		# Gnumeric spreadsheet
		'go' = '0'				# Go source code
		'gpg' = '9'				# GPG data (binary)
		'gz' = '9'				# Compressed data
		'hei[cf]' = 'I'			# HEIC image
		'hqx' = '4'				# BinHex archive
		'html?' = 'h'			# HTML document
		'icns' = 'I'			# macOS icon
		'ico' = 'I'				# Windows icon
		'img' = '9'				# Disk image
		'inf' = '0'				# Windows INF file
		'ini' = '0'				# Configuration file
		'ipsw' = '9'			# iOS/iPod software update
		'iso' = '9'				# CD image
		'jar' = '9'				# Java app
		'java' = '0'			# Java source code
		'jp2' = 'I'				# JPEG 2000 image
		'jpe?g' = 'I'			# JPEG image
		'js' = '0'				# JavaScript code
		'json' = '0'			# JSON data
		'jsonld' = '0'			# JSON-LD data
		'jxl' = 'I'				# JPEG XL image
		'lnk' = '5'				# Windows shortcut
		'log' = '0'				# Log
		'lua' = '0'				# Lua source code
		'lz' = '9'				# Compressed data
		'lzh' = '9'				# Compressed data
		'lzma' = '9'			# Compressed data
		'lzo' = '9'				# Compressed data
		'm3u8?' = '<'			# Playlist
		'm4' = '0'				# M4 source code
		'm4[abpr]' = '<'		# MPEG-4 audio formats (mostly iTunes)
		'm4v|mp4' = ';'			# MPEG-4 container (usually video)
		'md|markdown' = '0'		# Markdown text
		'midi?' = '<'			# MIDI music
		'mkv' = ';'				# Matroska video
		'mov' = ';'				# QuickTime movie
		'mp3' = '<'				# MP3 audio
		'mpe?g' = ';'			# MPEG movie
		'mpp' = 'd'				# Microsoft Project document
		'msp' = 'I'				# Microsoft Paintbrush image
		'numbers' = 'd'			# Numbers spreadsheet
		'o' = '9'				# Object file
		'ocx' = '5'				# ActiveX control
		'odb' = 'd'				# OpenDoucment database
		'odf' = 'd'				# OpenDocument formula
		'og[gm]' = '<'			# Ogg audio
		'ogv' = ';'				# Ogg video
		'ovl' = '5'				# DOS overlay
		'o?xps' = 'd'			# (Open)XPS document
		'pages' = 'd'			# Pages document
		'par2?' = '9'			# PAR archive
		'pas' = '0'				# Pascal code
		'pbm' = ':'				# PBM image
		'pi?ct' = 'I'			# Apple PICT image
		'pdf' = 'd'				# PDF document
		'pdn' = 'I'				# Paint.NET image
		'pem' = '0'				# PEM-encoded data
		'pfx|p12|p7[bc]' = '9'	# Certificates
		'php[345]?' = '0'		# PHP code
		'pl' = '0'				# Perl code
		'png' = 'I'				# PNG image
		'pptx?|pps|pot' = 'd'	# PowerPoint presentation
		'ps' = 'd'				# PostScript document
		'psd' = 'I'				# Photoshop image
		'psp' = 'I'				# Paint Shop Pro image
		'ps[cdm]?1' = '0'		# PowerShell code
		'ps1xml' = '0'			# PowerShell types or formats
		'pub' = 'd'				# Publisher document
		'py' = '0'				# Python code
		'py[co]' = '9'			# Python bytecode
		'r' = '0'				# R code
		'rar' = '9'				# WinRAR archive
		'rb' = '0'				# Ruby source code
		'rdp' = '0'				# Microsoft Remote Desktop connection
		'rss|atom' = '0'		# News feed
		'rtfd?' = 'd'			# Rich Text Format document
		'scr' = '5'				# Windows screen saver
		'scss' = '0'			# Sass code
		'sh|bash|command' = '0'	# Shell script
		'sht(?:ml)?' = 'h'		# HTML with includes
		'sitx?' = '9'			# Stuffit archive
		'snd' = '<'				# Sound
		'sql' = '0'				# SQL code
		'svgz?' = 'I'			# SVG image
		'sys|drv' = '5'			# DOS/Windows driver
		'tab|tsv' = 'd'			# Tab-encoded values
		'tar' = '9'				# TAR archive
		'targa|tga' = 'I'		# Targa image
		'tcl' = '0'				# TCL code
		'tex' = '0'				# Tex code
		'tiff?' = 'I'			# TIFF image
		'tt[cf]|otf|woff2?' = '9'	# Font
		'txt' = '0'				# Text
		'uue' = '6'				# UUEncoded data
		'vbs' = '0'				# VBScript
		'vhdx?' = '9'			# Windows disk image
		'vsdx?' = 'I'			# Visio drawing
		'wav' = '<'				# Wave audio
		'webm' = ';'			# WebM video
		'webp|wp2' = 'I'		# WebP (2) image
		'wim|esd' = '9'			# Windows Image (archive)
		'wma|asf' = ';'			# Windows Media audio
		'wmf|emf' = 'I'			# Windows Metafile image
		'wmv' = ';'				# Windows Media video
		'wpt?' = 'd'			# WordPerfect doucment
		'wri' = 'd'				# Windows Write document
		'xcf' = 'I'				# GIMP image
		'xht(?:ml)?' = 'h'		# XHTML code
		'xl(s[bmx]?|w)' = 'd'	# Excel document
		'xltm?'	= 'd'			# Excel template
		'xml|rdf' = '0'			# XML code
		'xpm' = 'I'				# XPM image
		'xsd' = '0'				# XSD code
		'xslt?' = '0'			# XML stylesheet
		'xz' = '9'				# Compressed data
		'ya?ml' = '0'			# YAML code
		'Z' = '9'				# Compressed data
		'zip' = '9'				# Zip archive
		'zoo' = '9'				# ZOO archive
		'123' = 'd'				# Lotus 1-2-3 document
		'7z' = '9'				# 7-zip archive
	}

	$Result = $null
	ForEach ($regex in $Extensions.GetEnumerator()) {
		# "Testing extension $Extension against $($regex.Name)."
		Write-Debug (Get-MessageTranslation 28 @($Extension, $regex.Name))
		If ($Extension -Match $regex.Name) {
			$Result = $regex.Value
			Break
		}
	}
	# "Guessing that the extension ___ is of type $(___ ?? 'unknown')."
	Write-Verbose (Get-MessageTranslation 29 @($Extension, ($Result ?? (Get-MessageTranslation 30))))
	Return $Result
}

Function Get-MessageTranslation {
	[OutputType([String])]
	Param(
		[Parameter(Position=0, Mandatory)]
		[UInt16] $MessageID,

		[Parameter(Position=1)]
		[AllowNull()]
		[String[]] $Substitutions = @()
	)

	If ($null -eq $script:Translations) {
		Import-Translation
	}

	Return ($script:Translations[$MessageID - 1] -f $Substitutions)
}

Function Import-Translation {
	# Error messages in this function indicate that a localization does
	# not exist, could not be loaded, or has not yet been loaded and any
	# lookup would cause an infinite loop.  Do not translate these
	# errors;  leave them in English.
	[CmdletBinding()]
	[OutputType([Void])]
	Param(
		[Switch] $ForceEnUs
	)

	$Language = (Get-Culture)

	Try {
		# "Attempting to load translations for <your language here>."
		Write-Debug "Attempting to load translations for $($Language.Name)"
		$File = Join-Path -Path (Get-Module 'PSGopher').ModuleBase -ChildPath $Language.Name -AdditionalChildPath 'translations.json'
		$script:Translations = Get-Content -Path $File -Encoding 'UTF8' | ConvertFrom-Json
	}
	Catch {
		If (-Not $ForceEnUs) {
			Write-Debug "Falling back to English (United States)"
			Import-Translation -ForceEnUs:$true
		}
		Else {
			Throw 'Failed to load en-US translation!'
		}
	}
	Return
}

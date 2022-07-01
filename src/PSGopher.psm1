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
	Write-Verbose "Connecting to $($Uri.Host)"
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

		$Uri = [Uri]::new("gopher://$($Uri.Host):$($Uri.Port)$Path")
	}
	
	# Otherwise, let's try and guess.
	Else {
		$ContentTypeExpected = (Get-GopherType ($Uri.AbsolutePath -Split '\.')[-1])
	}

	# If we still can't figure it out, assume it's a Gopher menu.
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
						$result = Convert-GopherLink $line -Server $Uri.Host -Port $Uri.Port
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
		'aac' = '<'
		'ace' = 9
		'ai' = 'I'
		'aif' = '<'
		'aifc' = '<'
		'aiff' = '<'
		'ani' = 5
		'apk' = 9
		'applescript' = 0
		'arj' = 9
		'art' = 'I'
		'asc' = 0
		'asf' = ';'
		'asm' = 0
		'ass' = 0
		'au' = '<'
		'av1' = ';'
		'avi' = ';'
		'avif' = 'I'
		'bash' = 0
		'bat' = 0
		'bin' = 9
		'bmp' = ':'
		'br' = 9
		'bz2' = 9
		'c' = 0
		'cab' = 9
		'cer' = 0
		'cfg' = 0
		'cgm' = 'I'
		'cmd' = 0
		'coffee' = 0
		'com' = 5
		'command' = 0
		'conf' = 0
		'cpio' = 9
		'cpp' = 0
		'crl' = 9
		'crt' = 9
		'cs' = 0
		'css' = 0
		'csv' = 0
		'cur' = 5
		'deb' = 9
		'der' = 0
		'dib' = ':'
		'diff' = 0
		'dll' = 5
		'dmg' = 9
		'dng' = 'I'
		'dns' = 0
		'doc' = 'd'
		'docm' = 'd'
		'docx' = 'd'
		'dot' = 'd'
		'dotm' = 'd'
		'dotx' = 'd'
		'dsk' = 9
		'dvi' = 'd'
		'dvr-ms' = ';'
		'dwg' = 'I'
		'ebuild' = 0
		'emf' = 'I'
		'eml' = 0
		'eps' = 'I'
		'epub' = 9
		'esd' = 9
		'exe' = 5
		'fodg' = 'd'
		'fodp' = 'd'
		'fods' = 'd'
		'fodt' = 'd'
		'fon' = 5
		'flac' = '<'
		'flv' = ';'
		'gif' = 'g'
		'gifv' = ';'
		'gmi' = 0
		'gnumeric' = 'd'
		'go' = 0
		'gpg' = 9
		'gz' = 9
		'h' = 0
		'heic' = 'I'
		'heif' = 'I'
		'hpp' = 0
		'hs' = 0
		'hqx' = 4
		'htm' = 'h'
		'html' = 'h'
		'hxx' = 0
		'ico' = 'I'
		'img' = 9
		'inf' = 0
		'ini' = 0
		'ipsw' = 9
		'iso' = 9
		'java' = 0
		'jp2' = 'I'
		'jpg' = 'I'
		'jpeg' = 'I'
		'js' = 0
		'json' = 0
		'jsonld' = 0
		'jxl' = 'I'
		'lnk' = 5
		'log' = 0
		'lua' = 0
		'lz' = 9
		'lzh' = 9
		'lzma' = 9
		'lzo' = 9
		'm3u' = '<'
		'm3u8' = '<'
		'm4' = 0
		'm4a' = '<'
		'm4b' = '<'
		'm4p' = '<'
		'm4r' = '<'
		'm4v' = ';'
		'markdown' = 0
		'md' = 0
		'mid' = '<'
		'midi' = '<'
		'mkv' = ';'
		'mobi' = 9
		'mov' = ';'
		'mp3' = '<'
		'mp4' = ';'	# can be audio or video
		'mpeg' = ';'
		'mpg' = ';'
		'msg' = 0
		'msp' = 'I'
		'o' = 9
		'ocx' = 5
		'odf' = 'd'
		'odg' = 'I'
		'odp' = 'd'
		'ods' = 'd'
		'odt' = 'd'
		'ogg' = '<'
		'ogm' = '<'
		'ogv' = ';'
		'otp' = 'd'
		'ovl' = 5
		'oxps' = 'd'
		'pages' = 'd'
		'par' = 9
		'par2' = 9
		'pas' = 0
		'pbm' = ':'
		'pct' = 'I'
		'pcx' = ':'
		'pdf' = 'd'		# I've seen "P" used, but that is non-standard.
		'pdn' = 'I'
		'pem' = 0
		'pfx' = 9
		'php' = 0
		'pict' = 'I'
		'pif' = 5
		'pl' = 0
		'png' = 'I'
		'pot' = 'd'
		'pps' = 'd'
		'ppt' = 'd'
		'pptx' = 'd'
		'ps' = 'd'
		'psd' = 'I'
		'psp' = 'I'
		'ps1' = 0
		'psc1' = 0
		'psd1' = 0
		'psm1' = 0
		'ps1xml' = 0
		'pub' = 'd'
		'py' = 0
		'pyc' = 9
		'pyo' = 9
		'p12' = 9
		'p7b' = 9
		'p7c' = 9
		'r' = 0
		'rar' = 9
		'raw' = 'I'
		'rb' = 0
		'rdf' = 0
		'rdp' = 0
		'rpm' = 9
		'rs' = 0
		'rss' = 0
		's' = 0
		'scpt' = 0
		'scr' = 5
		'scss' = 0
		'sh' = 0
		'shtml' = 'h'
		'sit' = 9
		'sitx' = 9
		'snd' = '<'
		'sql' = 0
		'srt' = 0
		'ssa' = 0
		'svg' = 'I'		# could also be 0
		'svgz' = 'I'
		'sys' = 5
		'tab' = 'd'
		'tar' = 9
		'targa' = 'I'
		'tcl' = 0
		'tex' = 0
		'tga' = 'I'
		'tif' = 'I'
		'tiff' = 'I'
		'ts' = 0
		'ttc' = 5
		'ttf' = 5
		'txt' = 0
		'uue' = 6
		'vbs' = 0
		'vhd' = 9
		'vhdx' = 9
		'vsd' = 'I'
		'vsdx' = 'I'
		'wav' = '<'
		'webm' = ';'
		'webp' = 'I'
		'wim' = 9
		'wma' = ';'
		'wmf' = 'I'
		'wmv' = ';'
		'wp2' = 'I'
		'wpd' = 'd'
		'wps' = 'd'
		'wpt' = 'd'
		'wri' = 'd'
		'xcf' = 'I'
		'xht' = 'h'
		'xhtml' = 'h'
		'xls' = 'd'
		'xlsb' = 'd'
		'xlsm' = 'd'
		'xlsx' = 'd'
		'xlt' = 'd'
		'xltm' = 'd'
		'xlw' = 'd'
		'xml' = 0
		'xpm' = 'I'
		'xps' = 'd'
		'xsd' = 0
		'xsl' = 0
		'xslt' = 0
		'xz' = 9
		'yaml' = 0
		'Z' = 9
		'zip' = 9
		'zoo' = 9
		'123' = 'd'
		'7z' = 9
	}

	$Result = $Extensions[$Extension]
	Write-Verbose "Guessing that the extension $Extension is of type $($Result ?? 'unknown')."
	Return $Result
}
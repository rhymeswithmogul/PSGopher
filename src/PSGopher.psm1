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
		'asc' = 0
		'avi' = ';'
		'avif' = 'I'
		'bmp' = ':'
		'br' = 9
		'bz2' = 9
		'c' = 0
		'cpp' = 0
		'cs' = 0
		'css' = 0
		'csv' = 0
		'dib' = ':'
		'dmg' = 9
		'doc' = 'd'
		'docx' = 'd'
		'dot' = 'd'
		'dotm' = 'd'
		'dotx' = 'd'
		'epub' = 9
		'fodg' = 'd'
		'fodp' = 'd'
		'fods' = 'd'
		'fodt' = 'd'
		'flac' = '<'
		'flv' = ';'
		'gif' = 'g'
		'gifv' = ';'
		'gmi' = 0
		'gpg' = 9
		'gz' = 9
		'h' = 0
		'hpp' = 0
		'hs' = 0
		'hqx' = 4
		'htm' = 'h'
		'html' = 'h'
		'ico' = 'I'
		'iso' = 9
		'jp2' = 'I'
		'jpg' = 'I'
		'jpeg' = 'I'
		'js' = 0
		'json' = 0
		'jxl' = 'I'
		'lzma' = 9
		'md' = 0
		'mkv' = ';'
		'mov' = ';'
		'mp3' = '<'
		'mp4' = ';'	# sometimes just audio
		'msp' = 'I'
		'odf' = 'd'
		'odg' = 'd'
		'odp' = 'd'
		'ods' = 'd'
		'odt' = 'd'
		'ogg' = '<'
		'ogv' = ';'
		'pcx' = ':'
		'pdf' = 'd'
		'pdn' = 'I'
		'pict' = 'I'
		'png' = 'I'
		'ppt' = 'd'
		'pptx' = 'd'
		'ps' = 'd'
		'py' = 0
		'rdf' = 0
		'rs' = 0
		'sh' = 0
		'sit' = 9
		'sql' = 0
		'svg' = 'I'		# could also be 0
		'svgz' = 'I'
		'tar' = 9
		'tif' = 'I'
		'tiff' = 'I'
		'txt' = 0
		'uue' = 6
		'wav' = '<'
		'webm' = ';'
		'webp' = 'I'
		'wp2' = 'I'
		'xhtml' = 'h'
		'xls' = 'd'
		'xlsb' = 'd'
		'xlsm' = 'd'
		'xlsx' = 'd'
		'xml' = 0
		'xpm' = 'I'
		'xsd' = 0
		'xsl' = 0
		'xz' = 9
		'zip' = 9
		'7z' = 9
	}

	$Result = $Extensions[$Extension]
	Write-Verbose "Guessing that the extension $Extension is of type $($Result ?? 'unknown')."
	Return $Result
}
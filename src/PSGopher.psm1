#Requires -Version 7.1
Function Invoke-GopherRequest {
	[CmdletBinding()]
	[Alias('igr')]
	Param(
		[Parameter(Mandatory)]
		[Alias('Url')]
		[ValidateNotNullOrEmpty()]
		[Uri] $Uri,

		[ValidateNotNullOrEmpty()]
		[IO.FileInfo] $OutFile,

		[Alias('UseTLS')]
		[Switch] $UseSSL,

		[ValidateSet('ASCII','UTF7','UTF8','UTF16','Unicode','UTF32')]
		[String] $Encoding = 'UTF8',

		[Switch] $Info,

		[ValidateNotNullOrEmpty()]
		[String] $Views
	)

	Set-StrictMode -Version Latest

	Write-Verbose "Connecting to $($Uri.Host)"
	$TcpSocket = [Net.Sockets.TcpClient]::new($Uri.Host, $Uri.Port ?? 70)
	$TcpStream = $TcpSocket.GetStream()
	$TcpStream.ReadTimeout = 2000 #milliseconds
	If ($UseSSL) {
		Write-Debug 'Upgrading connection to TLS'
		$secureStream = [Net.Security.SslStream]::new($TcpStream, $false)
		$secureStream.AuthenticateAsClient($Uri.Host)
		$TcpStream = $secureStream
	}

	# Strip the content type from the resource identifier.
	# It's not supposed to be sent to the server.
	$ContentTypeExpected = $null
	If ($Uri.AbsolutePath -CMatch "^\/[0123456789+gIT:;<dhis]\/") {
		$ContentTypeExpected = $Uri.AbsolutePath.Substring[1]
		$Path = $Uri.AbsolutePath.Substring(2)
		$Uri = [Uri]::new("gopher://$($Uri.Host):$($Uri.Port)$Path")
	}

	# Request the resource.
	$ToSend = $Uri.AbsolutePath
	If ($Info) {
		If ($Uri.AbsolutePath[-1] -eq '/') {
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

	# Set text encoding.  Gopher probably default 
	Switch ($Encoding) {
		'ASCII'   {$Encoder = [Text.AsciiEncoding]::new()}
		'UTF7'    {$Encoder = [Text.UTF7Encoding]::new()}
		'UTF8'    {$Encoder = [Text.UTF8Encoding]::new()}
		'UTF16'   {$Encoder = [Text.UnicodeEncoding]::new()}
		'Unicode' {$Encoder = [Text.UnicodeEncoding]::new()}
		'UTF32'   {$Encoder = [Text.UTF32Encoding]::new()}
		default   {Throw [NotImplementedException]::new('An unknown Encoder was specified.')}
	}

	# Read the full response.
	$BufferSize = 1024
	$buffer = New-Object Byte[] $BufferSize
	$response = ''

	$read = ''
	Write-Debug 'Beginning to read'
	Do {
		Write-Debug "Reading from the server."
		$read = $TcpStream.Read($buffer, 0, $BufferSize)
		If ($read -gt 0) {
			$response += $Encoder.GetString($buffer, 0, $read)
		}
	} While ($read -gt 0)
	Write-Verbose "Received $($Encoder.GetByteCount($response)) bytes from server."

	# Close connections.
	$writer.Close()
	$TcpSocket.Close()

	$StatusCode = 0
	$Content = ''
	$Links = @()

	$response -Split "(`r`n)" | ForEach-Object {
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

				'3' {
					Write-Error -Message $Content -TargetObject $Uri -ErrorId 3 -Category 'ResourceUnavailable'
					$StatusCode = 3
				}
		
				# All other Gopher links
				default {
					$result = Convert-GopherLink $line -Server $Uri.Host -Port $Uri.Port
					$Links += $result
				}
			}
		}
	}

	# If we are saving the output to a file, then we do not send anything to the
	# output buffer.  We save the Content to a file instead.
	If ($OutFile) {
		# Don't write output if an error occurred.
		If ($response[0] -eq '3') {
			Write-Error $Content
			Return $null
		} Else {
			Write-Verbose "Writing $($Encoder.GetByteCount($Content)) bytes to $OutFile"
			Set-Content -AsByteStream -Path:$OutFile -Value:$Content	
		}
		Return
	}
	ElseIf ($Info) {
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
							$Result | Add-Member -NotePropertyName $AttributeName -NotePropertyValue $AttributeValue.Split("`r`n", [StringSplitOptions]::RemoveEmptyEntries)
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
		Return [PSCustomObject]@{
			'StatusCode' = $StatusCode
			'StatusDescription' = ($StatusCode -eq 3 ? 'ERROR' : 'OK')
			'ContentType' = $ContentTypeExpected ?? 1
			'Content' = $Content
			'RawContent' = $response
			'Encoding' = $Encoder.GetType()
			'Images' = $Links | Where-Object {$_.Type -Eq 'g' -Or $_.Type -Eq 'I'}
			'Links' = $Links
			'RawContentLength' = $response.Length
		}
	}
}

Function Convert-GopherLink {
	Param(
		[Parameter(Mandatory)]
		[ValidateNotNullOrEmpty()]
		[ValidatePattern('^(?:.)(?:[^\t]*)\t')]
		[String] $InputObject,

		[String] $Server,

		[UInt16] $Port
	)

	$fields = $InputObject -Split "`t"
	$uri    = $null

	# Are we dealing with a /URL: link?  If so, we can easily create
	# the href [Uri].  Otherwise, we'll need to build it ourselves.
	If ($fields[1] -CLike 'URL:*' -or $fields[1] -CLike '/URL:*') {
		$uri = [Uri]::new($fields[1] -Replace [RegEx]"\/?URL:",'')
	}
	Else {
		$Server = ${fields}?[2] ?? $Server
		$Port   = ${fields}?[3] ?? $Port

		# Pick the appropriate URL schema for the link type.
		# For the first two (CCSO and Telnet), there should be nothing after the
		# optional port, but let's include it anyway.
		Switch -RegEx ($fields[0][0]) {
			'2'     {$Port ??= 105; $uri = [Uri]::new("cso://${Server}:$Port$($fields[1])")}
			'[8T]'  {$Port ??= 23;  $uri = [Uri]::new("telnet://${Server}:$Port$($fields[1])")}
			default {$Port ??= 70;  $uri = [Uri]::new("gopher://${Server}:$Port$($fields[1])")}
		}
	}

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
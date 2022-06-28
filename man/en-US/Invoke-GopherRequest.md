---
external help file: PSGopher-help.xml
Module Name: PSGopher
online version: https://github.com/rhymeswithmogul/PSGopher/blob/man/en-US/Invoke-GopherRequest.md
schema: 2.0.0
---

# Invoke-GopherRequest

## SYNOPSIS
Gets content from a Gopher or Gopher+ server on the Internet.

## SYNTAX

### ToScreen (Default)
```
Invoke-GopherRequest [-Uri] <Uri> [-UseSSL] [-Info] [-Views <String[]>] [-Encoding <String>]
 [-InputObject <String>] [<CommonParameters>]
```

### OutFile
```
Invoke-GopherRequest [-Uri] <Uri> [-UseSSL] [-Info] [-Views <String[]>] [-Encoding <String>]
 [-OutFile <String>] [-InputObject <String>] [<CommonParameters>]
```

## DESCRIPTION
The `Invoke-GopherRequest` cmdlet sends requests to a Gopher or Gopher+ server (with or without TLS).  It parses the response and returns collections of links, images, and metadata;  or, it can download files.

This cmdlet will make the best guess as to what type of file you will be requesting (based on extension).  However, it's recommended to supply the expected content type as part of the URI string.  For example, "gopher://example.com/0/file.txt" as opposed to "gopher://example.com/file.txt".

## EXAMPLES

### Example 1
This example will connect to Floodgap's Gopher server and return the content.

```powershell
PS> $response = Invoke-GopherRequest gopher://floodgap.com
PS> $response.Content

Welcome to Floodgap Systems' official gopher server.
Floodgap has served the gopher community since 1999
(formerly gopher.ptloma.edu).
[...]
```

### Example 2
The `-Info` parameter will retrieve attributes about a resource, if the server supports Gopher+.

```powershell
PS> igr -Info gopher://colincogle.name/blog/powershell-7/powershell-7-for-programmers.txt

INFO                                                                                                       ADMIN
----                                                                                                       -----                     
0powershell-7-for-programmers.txt       /blog/powershell-7/powershell-7-for-programmers.txt     colincogle.name 70      + {Admin: Colin Cogle <coli…
```

To save typing, `igr` is an alias for this command.

### Example 3
The `-UseSSL` parameter will require SSL/TLS or the cmdlet will fail.  By using pipeline chaining operators, you can have the command retry without SSL/TLS.

```powershell
PS C:\> $uri = 'gopher://floodgap.org'
PS C:\> Invoke-GopherRequest $uri -UseSSL || Invoke-GopherRequest $uri
```

### Example 4
You can download files with the `-OutFile` parameter.

```powershell
PS C:\> Invoke-GopherRequest 'gopher://example.org/images/coolpic.gif' -OutFile 'coolpic.gif'
```

### Example 5
If you need to supply input to a Gopher server (for example, a search engine), use the `-InputObject` parameter.  Input specified this way will be automatically URL-encoded.

```powershell
PS C:\> Invoke-GopherRequest 'gopher://gopher.floodgap.com/7/v2/vs' -InputObject 'search query'
```

## PARAMETERS

### -Encoding
When using `-OutFile` to download text files, specifies the type of encoding for the target file.  Supported encodings are:
	- ASCII : Uses the encoding for the ASCII (7-bit) character set.
	- UTF7  : Encodes in UTF-7 format.
	- UTF8  : Encodes in UTF-8 format.  This is the default.
	- UTF16 : Encodes in UTF-16 format using the little-endian byte order.
	- UTF32 : Encodes in UTF-32 format.

Historically, Gopher only supported ASCII.  However, UTF8 is the default option for this cmdlet, as that is the most common encoding these days.

If the file being downloaded is expected to be binary, this parameter has no effect.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: ASCII, UTF7, UTF8, UTF16, Unicode, UTF32

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Info
Instead of fetching the contents of the remote resource, this will make the cmdlet send a Gopher+ request to retrieve only attributes about the item instead.  This will return a `PSCustomObject` containing attributes such as INFO, ADMIN, ABSTRACT, and VIEWS.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: Abstract, Admin, Attributes, Information

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -OutFile
Specifies the output file for which this cmdlet saves the response body.  Enter a path and file name.  If you omit the path, the default is the current location.

```yaml
Type: String
Parameter Sets: OutFile
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Uri
Specifies the Uniform Resource Identifier (URI) of the Gopher resource to which this request is sent. Enter a URI.  This parameter supports the "gopher" scheme only.  For secure Gopher, add the -UseSSL parameter instead.
        
This parameter is required. The parameter name Uri is optional.

```yaml
Type: Uri
Parameter Sets: (All)
Aliases: Url

Required: True
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -UseSSL
Requires this Gopher connection to use SSL/TLS.  All SSL/TLS protocols enabled in the current session are allowed.

If the remote server does not support secure connections, this cmdlet will intentionally fail.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: UseTLS

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Views
When using Gopher+, you can request that your content be delivered in this specified MIME type.  The server will make its best effort to supply your document in that format, if it can.  All servers should support "text/plain".

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -InputObject
To send data to the Gopher server -- for example, when using a search engine -- the simplest way is to specify it with this parameter.  Any input will be automatically URL-encoded and appended to the URL.

Due to how the PowerShell runtime handles non-HTTP(S) URIs, it is not recommended to write the URL yourself.  Please use this parameter instead.

```yaml
Type: String
Parameter Sets: (All)
Aliases: Post, PostData, Query, QueryString

Required: False
Position: Named
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String
Any strings passed to this cmdlet will be used as the `-InputObject` parameter value.

## OUTPUTS

### System.Object
## NOTES

## RELATED LINKS

[about_PSGopher](about_PSGopher)
[Invoke-WebRequest](Invoke-WebRequest)
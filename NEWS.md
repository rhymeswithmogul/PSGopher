# PSGopher News

## Version 2.0.0
-  PSGopher has fixed a major oversight involving content types to bring it into compliance with the Gopher specification.   All types are now reporting as characters instead of numbers (i.e., `'1'` (ASCII 49) instead of `1` (0x01)).
-  PSGopher now supports translations.
-  Pester tests are now included, to verify tha the module works.

## Version 1.3.3
More conceptual help has been added so you can learn more about Gopher, Gopher+, and the Gopher URI scheme.  The cmdlet itself has not changed.

## Version 1.3.2
-  The SecureGopher TLS connection information is now shown in the debug stream.
-  Updated conceptual help to note that the .NET runtime does validate a server's certificate.

## Version 1.3.1
Update conceptual help.

## Version 1.3.0
-  The nonstandard `sgopher` and `gopher+tls` URL schemes are now supported, and will imply the `-UseSSL` parameter.
-  The `-TrySSL` parameter has been introducted. This will attempt a secure connection, but unlike `-UseSSL`, if a secure connection fails, it will fall back to a non-secured one.  (Security-conscious users may want to set this as a default parameter in their `$PROFILE`.)

## Version 1.2.0
-  The non-standard `gophers` (Gopher + TLS) URL scheme is supported, and will imply the `-UseSSL` parameter.
-  You may use query parameters in addition to `-InputObject`.
-  Add more extensions to the type guesser.
-  Changed the type guesser to use regular expressions.
-  Verbose and Debug preferences are now applied inside helper functions.

## Version 1.1.1
Fixes a bug where query strings might be erroneously detected and sent to the server, causing resource lookups to fail.

## Version 1.1
Adds support for Gopher query strings via the `-InputObject` parameter.  Previously, one would have to form their own URL with a query string.

## Version 1.0.2
-  Fixes a bug where the content type negotiation fails when the second character of the URL is not a forward slash.  For example, `gopher://example.com/0/textfile.txt` would work, but `gopher://example.com/0textfile.txt` would not have worked.
-  Fixes a bug where non-URL links were missing from the `Links` property.
-  More file types are recognized by the content type guesser, such as OpenDocument and gemtext documents.

## Version 1.0.1
There are no user-visible changes.  Only the documentation was updated.

## Version 1.0.0
PSGopher's first release.

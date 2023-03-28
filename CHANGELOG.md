# PSGopher ChangeLog

## Version 2.0.0
-  Added support for language translations!  Create a file called `translations.json` in this module's language folder, and this script will find it (e.g., `en-US/translations.json`).  Please contribute them on GitHub!
-  Fixed content type reporting.  Now, types are always an ASCII character, and never a number.  This is in line with the Gopher specification.  For example, the Gophermap type will be reported correctly as `'1'` (ASCII 49) instead of `1` (1).  Please update any code that relies on this module.
-  Added Pester tests.
-  Fixed a bug where explicit content types might be returned as plain text when they are in fact Gopher menus.
-  Fixed a bug where saving files with `-OutFile` might throw an error under some circumstances.
-  Fixed a bug where the `Content` property would not contain correct data when using Gopher+ views.
-  Remove `Desktop` from `PSCompatibleEditions`.  This module has required PowerShell 7 since the beginning, and was never compatible with downlevel versions.

## Version 1.3.3
-  Added the Gopher RFCs and non-RFCs as conceptual help items:  `about_Gopher`, `about_Gopher+`, and `about_GopherUriScheme`.

## Version 1.3.2
-  When using SecureGopher, the debug stream now shows the TLS protocol version and negotiated cipher/ciphersuite.
-  Updated an error in the conceptual help.  The .NET runtime does indeed validate server certificates, even if this app does not do it

## Version 1.3.1
-  Updated an error in the conceptual help.  SecureGopher does, in fact, present a certificate.

## Version 1.3.0
-  Opportunistic TLS can be enabled with the `-TrySSL` parameter.
-  The non-standard `sgopher` and `gopher+tls` URL schemes are now supported.

## Version 1.2.0
-  The non-standard `gophers` (Gopher + TLS) URL scheme is now supported.
-  More extensions are supported by the type guesser.
-  Also, for ease of development, the type guesser now supports regular expressions internally.
-  `VerbosePreference` and `DebugPreference` are now supported in helper functions.
-  Improve URL query parameter handling.  Also, you may now use `-InputObject` with in-URL query parameters.

## Version 1.1.1
Fixes a bug where query strings might be erroneously detected and sent to the server, causing resource lookups to fail.

## Version 1.1.0
Adds support for Gopher query strings via the `-InputObject` parameter.  Previously, one would have to make their own URL by hand to do this.

## Version 1.0.1
Documentation updates.

## Version 1.0.0
Released December 5, 2021, this is the initial release.
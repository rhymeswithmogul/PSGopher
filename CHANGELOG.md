# PSGopher ChangeLog

## Next Version
- The non-standard `gophers` (Gopher + TLS) URL scheme is now supported.
- More extensions are supported by the type guesser.
- Also, for ease of development, the type guesser now supports regular expressions internally.
- `VerbosePreference` and `DebugPreference` are now supported in helper functions.

## Version 1.1.1
Fixes a bug where query strings might be erroneously detected and sent to the server, causing resource lookups to fail.

## Version 1.1.0
- Adds support for Gopher query strings via the `-InputObject` parameter.  Previously, one would have to make their own URL by hand to do this.

## Version 1.0.1
Documentation updates.

## Version 1.0.0
Released December 5, 2021, this is the initial release.
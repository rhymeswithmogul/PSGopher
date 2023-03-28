<#
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

# Module manifest for module 'PSGopher'
# Generated by: Colin Cogle
# Generated on: December 2, 2021

@{

# Script module or binary module file associated with this manifest.
RootModule = 'src/PSGopher.psm1'

# Version number of this module.
ModuleVersion = '2.0.0'

# Supported PSEditions
CompatiblePSEditions = @('Core')

# ID used to uniquely identify this module
GUID = '81001589-9a2a-4554-a07b-fe0ffd4b9b50'

# Author of this module
Author = 'Colin Cogle <colin@colincogle.name>'

# Copyright statement for this module
Copyright = '(c) 2021-2023 Colin Cogle. Licensed under the AGPL, version 3 or later.'

# Description of the functionality provided by this module
Description = 'Connect to Gopher and Gopher+ servers.'

# Minimum version of the PowerShell engine required by this module
PowerShellVersion = '7.1'

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @('Invoke-GopherRequest')

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = ''

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @('igr')

# List of all files packaged with this module
FileList = @(
	'en-US/about_Gopher.help.txt',
	'en-US/about_Gopher+.help.txt',
	'en-US/about_GopherUriScheme.help.txt',
	'en-US/about_PSGopher.help.txt',
	'en-US/PSGopher-help.xml',
	'en-US/translations.json',
	'src/PSGopher.psm1',
	'tests/gopher.avif',
	'tests/PSGopherTest.txt',
	'AUTHORS.md',
	'CHANGELOG.md',
	'INSTALL.md',
	'LICENSE',
	'NEWS.md',
	'PSGopher.psd1',
	'PSGopher.Tests.ps1',
	'README.md'
)

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

	PSData = @{

		# Tags applied to this module. These help with module discovery in online galleries.
		Tags = @('Gopher', 'GopherPlus', 'Gopher+', 'SecureGopher', 'SecureGopher+', 'GopherS', 'SGopher', 'Gopher-TLS', 'download', 'igr', 'Overbite', 'port70', 'RFC1436', 'RFC4266', 'small_web', 'cURL', 'SSL', 'TLS', 'Windows', 'macOS', 'Linux')

		# A URL to the license for this module.
		LicenseUri = 'https://www.gnu.org/licenses/agpl-3.0.en.html'

		# A URL to the main website for this project.
		ProjectUri = 'https://github.com/rhymeswithmogul/PSGopher'

		# A URL to an icon representing this module.
		# IconUri = ''

		# ReleaseNotes of this module
		ReleaseNotes = "-  Added support for language translations!  Create a file called 'translations.json' in this module's language folder, and this script will find it (e.g., 'en-US/translations.json').  Please contribute them on GitHub!
		-  Fixed content type reporting.  Now, types are always an ASCII character, and never a number.  This is in line with the Gopher specification.  For example, the Gophermap type will be reported correctly as '1' (ASCII 49) instead of 1 (0x1).  Please update any code that relies on this module.
		-  Added Pester tests.
		-  Fixed a bug where explicit content types might be returned as plain text when they are in fact Gopher menus.
		-  Fixed a bug where saving binary files with '-OutFile' might throw an error under some circumstances.
		-  Fixed a bug where saving text files with '-OutFile' might append an additional CR+LF.
		-  Fixed a bug where the 'Content' property would not contain correct data when using Gopher+ views.
		-  Fixed a bug where generic images (those of type 'I') would not be detected as images, due to PowerShell's 'Switch' blocks being case-insensitive, even when using regular expressions.
		-  Remove 'Desktop' from 'PSCompatibleEditions'.  This module has required PowerShell 7 since the beginning, and was never compatible with downlevel versions.
		-  Cleaned up minor things reported by PSScriptAnalyzer."

		# Prerelease string of this module
		# Prerelease = 'git'

		# Flag to indicate whether the module requires explicit user acceptance for install/update/save
		RequireLicenseAcceptance = $false

		# External dependent modules of this module
		ExternalModuleDependencies = @()

	} # End of PSData hashtable

} # End of PrivateData hashtable

}


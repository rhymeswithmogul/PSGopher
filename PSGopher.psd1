# Module manifest for module 'PSGopher'
# Generated by: Colin Cogle
# Generated on: December 2, 2021
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'src/PSGopher.psm1'

# Version number of this module.
ModuleVersion = '1.0.1'

# Supported PSEditions
CompatiblePSEditions = @('Core', 'Desktop')

# ID used to uniquely identify this module
GUID = '81001589-9a2a-4554-a07b-fe0ffd4b9b50'

# Author of this module
Author = 'Colin Cogle <colin@colincogle.name>'

# Copyright statement for this module
Copyright = '(c) 2021 Colin Cogle. Licensed under the AGPL, version 3 or later.'

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
	'en-US/about_PSGopher.help.txt',
	'en-US/PSGopher-help.xml',
	'src/PSGopher.psm1',
	'AUTHORS',
	'CHANGELOG.md',
	'COPYING',
	'INSTALL',
	'LICENSE',
	'NEWS',
	'PSGopher.psd1',
	'README.md'
)

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

	PSData = @{

		# Tags applied to this module. These help with module discovery in online galleries.
		Tags = @('Gopher', 'GopherPlus', 'Gopher+', 'igr')

		# A URL to the license for this module.
		LicenseUri = 'https://www.gnu.org/licenses/agpl-3.0.en.html'

		# A URL to the main website for this project.
		ProjectUri = 'https://github.com/rhymeswithmogul/PSGopher'

		# A URL to an icon representing this module.
		# IconUri = ''

		# ReleaseNotes of this module
		ReleaseNotes = 'First release!  Enjoy!'

		# Prerelease string of this module
		# Prerelease = ''

		# Flag to indicate whether the module requires explicit user acceptance for install/update/save
		RequireLicenseAcceptance = $false

		# External dependent modules of this module
		ExternalModuleDependencies = @()

	} # End of PSData hashtable

} # End of PrivateData hashtable

}


# This file is part of PSGopher.
#
# PSGopher is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# PSGopher is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License
# along with PSGopher. If not, see <https://www.gnu.org/licenses/>.

#Requires -Modules @{ModuleName='Pester'; ModuleVersion='5.0.0'}

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'ModuleHelpFile',	Justification='Variable is used in another scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'psm1File',			Justification='Variable is used in another scope.')]
Param()

BeforeAll {
	Import-Module -Name (Join-Path -Path '.' -ChildPath 'PSGopher.psd1') -ErrorAction Stop
}

Context 'Validate the module files' {
	BeforeAll {
		$psm1File       = Join-Path -Path 'src'   -ChildPath 'PSGopher.psm1'
		$ModuleHelpFile = Join-Path -Path 'en-US' -ChildPath 'PSGopher-help.xml'
	}
	It 'has a module manifest' {
		'PSGopher.psd1' | Should -Exist
	}
	It 'has a root module' {
		$psm1File | Should -Exist
	}
	It 'has a valid root module' {
		$code = Get-Content -Path $psm1File -ErrorAction Stop
		$errors = $null
		$null = [Management.Automation.PSParser]::Tokenize($code, [ref]$errors)
		$errors.Count | Should -Be 0
	}
	It 'has a conceptual help file' {
		Join-Path -Path 'en-US' -ChildPath 'about_PSGopher.help.txt' | Should -Exist
	}
	It 'has a module help file' {
		$ModuleHelpFile | Should -Exist
	}
	It 'has a valid module help file' {
		$code = [Xml](Get-Content -Path $ModuleHelpFile -ErrorAction Stop)
		$code.Count | Should -Be 1
	}
}

Describe 'Invoke-GopherRequest' {
	BeforeAll {
		$script:Gophermap = $null
		$script:gif = $null
		$script:SHA256 = [Security.Cryptography.SHA256]::Create()
	}
	It 'Can fetch a text file' {
		$TxtTest = (Invoke-GopherRequest -Uri 'gopher://colincogle.name/0/PSGopherTest/PSGopherTest.txt')
		$TxtTest.ContentType | Should -Be '0'
		$TxtTest.Images | Should -BeNullOrEmpty
		$TxtTest.Links | Should -BeNullOrEmpty
		$TxtTest.Protocol | Should -Be 'Gopher'
		$TxtTest.RawContent | Should -Be $TxtTest.Content
		$TxtTest.RawContentLength | Should -Be 403

		# Hash the stream for correctness.
		$GoodHash = (Get-FileHash -Path (Join-Path -Path 'tests' -ChildPath 'PSGopherTest.txt')).Hash
		$ByteArray1 = [Text.Encoding]::UTF8.GetBytes($TxtTest.Content)
		$ByteArray2 = [Text.Encoding]::UTF8.GetBytes($TxtTest.RawContent)
		[BitConverter]::ToString($SHA256.ComputeHash($ByteArray1)) -Replace '-' | Should -Be $GoodHash
		[BitConverter]::ToString($SHA256.ComputeHash($ByteArray2)) -Replace '-' | Should -Be $GoodHash
	}
	It 'Can fetch a text file securely' {
		$SecureTxtTest = (Invoke-GopherRequest -Uri 'gophers://colincogle.name/0/PSGopherTest/PSGopherTest.txt')
		$SecureTxtTest.ContentType | Should -Be '0'
		$SecureTxtTest.Images | Should -BeNullOrEmpty
		$SecureTxtTest.Links | Should -BeNullOrEmpty
		$SecureTxtTest.Protocol | Should -Be 'SecureGopher'
		$SecureTxtTest.RawContent | Should -Be $SecureTxtTest.Content
		$SecureTxtTest.RawContentLength | Should -Be 403

		# Hash the stream for correctness.
		$GoodHash = (Get-FileHash -Path (Join-Path -Path 'tests' -ChildPath 'PSGopherTest.txt')).Hash
		$ByteArray1 = [Text.Encoding]::UTF8.GetBytes($SecureTxtTest.Content)
		$ByteArray2 = [Text.Encoding]::UTF8.GetBytes($SecureTxtTest.RawContent)
		[BitConverter]::ToString($SHA256.ComputeHash($ByteArray1)) -Replace '-' | Should -Be $GoodHash
		[BitConverter]::ToString($SHA256.ComputeHash($ByteArray2)) -Replace '-' | Should -Be $GoodHash
	}
	It 'Can download a text file correctly' {
		$TempFile = New-TemporaryFile
		Invoke-GopherRequest -Uri 'gophers://colincogle.name/0/PSGopherTest/PSGopherTest.txt' -OutFile $TempFile

		# Hash the file for correctness.
		# This is the same PSGopherTest.txt file that is included in the tests/ folder.
		$GoodHash = (Get-FileHash -Path (Join-Path -Path 'tests' -ChildPath 'PSGopherTest.txt')).Hash
		(Get-FileHash -Path $TempFile).Hash | Should -Be $GoodHash

		Remove-Item -Path $TempFile -ErrorAction SilentlyContinue
	}
	It 'Can fetch binaries correctly' {
		$imgTest = (Invoke-GopherRequest -Uri 'gopher://colincogle.name/I/PSGopherTest/gopher.avif')
		$imgTest.ContentType | Should -Be 'I'
		$imgTest.RawContentLength | Should -Be 2300

		# Hash the stream for correctness.
		# This is the same gopher.avif file that is included in the tests/ folder.
		$GoodHash = (Get-FileHash -Path (Join-Path -Path 'tests' -ChildPath 'gopher.avif')).Hash
		$SHA256 = [Security.Cryptography.SHA256]::Create()
		[BitConverter]::ToString($SHA256.ComputeHash($imgTest.Content)) -Replace '-' | Should -Be $GoodHash
		[BitConverter]::ToString($SHA256.ComputeHash($imgTest.RawContent)) -Replace '-' | Should -Be $GoodHash
	}
	It 'Can download binaries correctly' {
		$TempFile = New-TemporaryFile
		Invoke-GopherRequest -Uri 'gopher://colincogle.name/I/PSGopherTest/gopher.avif' -OutFile $TempFile

		# Hash the file for correctness.
		# This is the same gopher.avif file that is included in the tests/ folder.
		$GoodHash = (Get-FileHash -Path (Join-Path -Path 'tests' -ChildPath 'gopher.avif')).Hash
		(Get-FileHash -Path $TempFile).Hash | Should -Be $GoodHash

		Remove-Item -Path $TempFile -ErrorAction SilentlyContinue
	}
	It 'Can fetch a Gophermap' {
		$script:Gophermap = (Invoke-GopherRequest -Uri 'gopher://colincogle.name/1/PSGopherTest')
		$Gophermap.Protocol | Should -Be 'Gopher'
	}
	It 'Can parse a Gophermap' {
		$Gophermap.ContentType | Should -Be '1'
		$Gophermap.Images.Count | Should -Be 2
		$GopherMap.Links.Count | Should -Be 4
	}
	It 'Can parse images' {
		$img = $Gophermap.Images | Where-Object href -Like '*.avif'
		$img.href | Should -Be 'gopher://colincogle.name//PSGopherTest/gopher.avif'
		$img.Type | Should -Be 'I'
		$img.Description | Should -Be 'This is an image of a Gopher (AVIF).'
		$img.Resource | Should -Be '//PSGopherTest/gopher.avif'
		$img.Server | Should -Be 'colincogle.name'
		$img.Port | Should -Be 70
		$img.UrlLink | Should -BeFalse
	}
	It 'Can parse Gopher links' {
		$img = $Gophermap.Links | Where-Object href -Like '*.avif'
		$img.href | Should -Be 'gopher://colincogle.name//PSGopherTest/gopher.avif'
		$img.Type | Should -Be 'I'
		$img.Description | Should -Be 'This is an image of a Gopher (AVIF).'
		$img.Resource | Should -Be '//PSGopherTest/gopher.avif'
		$img.Server | Should -Be 'colincogle.name'
		$img.Port | Should -Be 70
		$img.UrlLink | Should -BeFalse
	}
	It 'Can parse URL links' {
		$github = $Gophermap.Links | Where-Object Type -eq 'h'
		$github.href | Should -Be 'https://github.com/rhymeswithmogul/PSGopher'
		$github.Type | Should -Be 'h'
		$github.Description | Should -Be 'View the project page on GitHub.'
		$github.Resource | Should -Be '/rhymeswithmogul/PSGopher'
		$github.Server | Should -Be 'github.com'
		$github.Port | Should -Be 443
		$github.UrlLink | Should -BeTrue
	}

	It 'Can fetch Gopher+ requests and parse INFO fields' {
		$script:Plus = Invoke-GopherRequest -Uri 'gopher://colincogle.name/I/PSGopherTest/gopher.avif' -Info
		$Plus.INFO  | Should -Be "Igopher.avif`t/PSGopherTest/gopher.avif`tcolincogle.name`t70`t+"
	}

	It 'Can fetch Gopher+ requests and parse ADMIN fields' {
		$Plus.ADMIN[0] | Should -Be 'Admin: Colin Cogle <colin@colincogle.name>'
		$Plus.ADMIN[1] | Should -BeLike 'Mod-Date: *'
	}

	It 'Can fetch and receive resources with Gopher+ views' {
		$Views = Invoke-GopherRequest -Uri 'gopher://colincogle.name/I/PSGopherTest/gopher.avif' -Views 'image/avif'
		$Views.Protocol | Should -Be 'Gopher+'
		$Views.ContentType | Should -Be 'I'
		$Views.RawContentLength | Should -Be 2307

		# Hash the stream for correctness.
		# This is the same gopher.avif file that is included in the tests/ folder.
		$GoodHash = (Get-FileHash -Path (Join-Path -Path 'tests' -ChildPath 'gopher.avif')).Hash
		$SHA256 = [Security.Cryptography.SHA256]::Create()
		[BitConverter]::ToString($SHA256.ComputeHash($Views.Content)) -Replace '-' | Should -Be $GoodHash
	}

	It 'Can fetch Gopher+ abstracts' {
		$Test = Invoke-GopherRequest -Uri 'gopher://colincogle.name/I/PSGopherTest/gopher.avif' -Abstract
		$Test.ABSTRACT | Should -Be 'This is a picture of a Minnesota Golden Gopher.'
	}
}

AfterAll {
	Remove-Module -Name 'PSGopher' -ErrorAction Ignore
}

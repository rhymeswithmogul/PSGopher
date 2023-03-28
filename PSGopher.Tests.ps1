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

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'Gophermap',			Justification='Variable is used in another scope.')]
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
	}
	It 'Can download a text file via Gopher' {
		$TxtTest = (Invoke-GopherRequest -Uri 'gopher://colincogle.name/0/PSGopherTest/PSGopherTest.txt')
		$TxtTest.ContentType | Should -Be '0'
		$TxtTest.Images | Should -BeNullOrEmpty
		$TxtTest.Links | Should -BeNullOrEmpty
		$TxtTest.Protocol | Should -Be 'Gopher'
		$TxtTest.RawContent | Should -Be $TxtTest.Content
	}
	It 'Can download a text file via SecureGopher' {
		$SecureTxtTest = (Invoke-GopherRequest -Uri 'gophers://colincogle.name/0/PSGopherTest/PSGopherTest.txt')
		$SecureTxtTest.ContentType | Should -Be '0'
		$SecureTxtTest.Images | Should -BeNullOrEmpty
		$SecureTxtTest.Links | Should -BeNullOrEmpty
		$SecureTxtTest.Protocol | Should -Be 'SecureGopher'
		$SecureTxtTest.RawContent | Should -Be $SecureTxtTest.Content
	}
	It 'Can fetch binaries correctly' {
		$GifTest = (Invoke-GopherRequest -Uri 'gopher://colincogle.name/g/PSGopherTest/gopher.gif')
		$GifTest.ContentType | Should -Be 'g'
		$GifTest.RawContentLength | Should -Be 16829

		# Hash the file for correctness.
		# This is the same gopher.gif file that is included in the tests/ folder.
		$GoodHash = (Get-FileHash -Path (Join-Path -Path 'tests' -ChildPath 'gopher.gif')).Hash
		$SHA256 = [Security.Cryptography.SHA256]::Create()
		[BitConverter]::ToString($SHA256.ComputeHash($GifTest.Content)) -Replace '-' | Should -Be $GoodHash
		[BitConverter]::ToString($SHA256.ComputeHash($GifTest.RawContent)) -Replace '-' | Should -Be $GoodHash
	}
	It 'Can download binaries correctly' {
		$TempFile = New-TemporaryFile
		Invoke-GopherRequest -Uri 'gopher://colincogle.name/g/PSGopherTest/gopher.gif' -OutFile $TempFile

		# Hash the file for correctness.
		# This is the same gopher.gif file that is included in the tests/ folder.
		$GoodHash = (Get-FileHash -Path (Join-Path -Path 'tests' -ChildPath 'gopher.gif')).Hash
		(Get-FileHash -Path $TempFile).Hash | Should -Be $GoodHash

		Remove-Item -Path $TempFile -ErrorAction SilentlyContinue
	}
	It 'Can fetch a Gophermap' {
		$script:Gophermap = (Invoke-GopherRequest -Uri 'gopher://colincogle.name/1/PSGopherTest')
		$Gophermap.Protocol | Should -Be 'Gopher'
	}
	It 'Can parse a Gophermap' {
		$Gophermap.ContentType | Should -Be '1'
		$Gophermap.Images.Count | Should -Be 1
		$GopherMap.Links.Count | Should -Be 3
	}
	It 'Can parse images' {
		$gif = $Gophermap.Images[0]
		$gif.href | Should -Be 'gopher://colincogle.name//PSGopherTest/gopher.gif'
		$gif.Type | Should -Be 'g'
		$gif.Description | Should -Be 'This is an animated GIF of a Gopher.'
		$gif.Resource | Should -Be '//PSGopherTest/gopher.gif'
		$gif.Server | Should -Be 'colincogle.name'
		$gif.Port | Should -Be 70
		$gif.UrlLink | Should -BeFalse
	}
	It 'Can parse Gopher links' {
		$gif = $Gophermap.Links | Where-Object Type -eq 'g'
		$gif.href | Should -Be 'gopher://colincogle.name//PSGopherTest/gopher.gif'
		$gif.Type | Should -Be 'g'
		$gif.Description | Should -Be 'This is an animated GIF of a Gopher.'
		$gif.Resource | Should -Be '//PSGopherTest/gopher.gif'
		$gif.Server | Should -Be 'colincogle.name'
		$gif.Port | Should -Be 70
		$gif.UrlLink | Should -BeFalse
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
}

AfterAll {
	Remove-Module -Name 'PSGopher' -ErrorAction Ignore
}

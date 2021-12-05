# PSGopher
A Gopher/Gopher+ client written in PowerShell.

## Installation
Grab it from PowerShell Gallery with: `Install-Module PSGopher`

## Usage
In this example, we'll connect to Floodgap's Gopher server and return the content.

```powershell
PS C:\> $response = Invoke-GopherRequest gopher://floodgap.com
PS C:\> $response.Content

Welcome to Floodgap Systems' official gopher server.
Floodgap has served the gopher community since 1999
(formerly gopher.ptloma.edu).
[…]
```
# Installing PSGopher

## PowerShell Gallery
The simplest way is to install from PowerShell Gallery:

```powershell
PS> Install-Module PSGopher
```

## Manually
If you are not installing from the PowerShell Gallery, simply copy all of these
files into your `$env:PSModulePath`.  For example:

```powershell
PS> Copy-Item -Recurse . C:\Users\you\Documents\PowerShell\Modules\PSGopher\
```

Then restart PowerShell.
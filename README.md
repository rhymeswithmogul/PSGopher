[![PowerShell Gallery Version (including pre-releases)](https://img.shields.io/powershellgallery/v/PSGopher?include_prereleases)](https://powershellgallery.com/packages/PSGopher/) [![PowerShell Gallery](https://img.shields.io/powershellgallery/dt/PSGopher)](https://powershellgallery.com/packages/v/PSGopher)

# PSGopher
A Gopher/Gopher+/SecureGopher client written for Powershell 7 and newer.

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

The syntax and output of this cmdlet is modeled after `Invoke-WebRequest`, going as far as to emulate some of its properties:

```powershell
PS /home/colin> Invoke-GopherRequest gopher://port70.net

Protocol         : Gopher
ContentType      : 1
Content          : Welcome to the gopher server at port70.net.
                   
                   Projects:
                   mgod gopher server
                   [HTTP] FRTPLOT: Free Real-time Data Plotter
                   [HTTP] Animator - Simple 2D Vector Graphics Interpreter
                   [HTTP] Plumb - connect multiple programs with lots of pipes
                   [HTTP] cchan - "channel" construct for inter-thread communication in C programs
                   [HTTP] Stutter (LISP interpreter)
                   
                   NECRON card game
                   Gopherchan!
                   
                   
                   
Encoding         : System.Text.UTF8Encoding
Images           : 
Links            : {@{href=gopher://port70.net/mgod; Type=1; Description=mgod gopher server; Resource=/mgod; 
                   Server=port70.net; Port=70; UrlLink=False}, @{href=http://frtplot.port70.net/; Type=h; 
                   Description=[HTTP] FRTPLOT: Free Real-time Data Plotter; Resource=/; Server=frtplot.port70.net; 
                   Port=80; UrlLink=True}, @{href=http://repo.hu/projects/animator; Type=h; Description=[HTTP] 
                   Animator - Simple 2D Vector Graphics Interpreter; Resource=/projects/animator; Server=repo.hu; 
                   Port=80; UrlLink=True}, @{href=http://repo.hu/projects/plumb; Type=h; Description=[HTTP] Plumb - 
                   connect multiple programs with lots of pipes; Resource=/projects/plumb; Server=repo.hu; Port=80; 
                   UrlLink=True}…}
RawContent       : iWelcome to the gopher server at port70.net. fake    (NULL)  0
                   i    fake    (NULL)  0
                   iProjects:   fake    (NULL)  0
                   1mgod gopher server  mgod    port70.net      70
                   h[HTTP] FRTPLOT: Free Real-time Data Plotter URL:http://frtplot.port70.net   port70.net      70
                   h[HTTP] Animator - Simple 2D Vector Graphics Interpreter     URL:http://repo.hu/projects/animator
                   port70.net   70
                   h[HTTP] Plumb - connect multiple programs with lots of pipes URL:http://repo.hu/projects/plumb
                   port70.net   70
                   H[HTTP] cchan - "channel" construct for inter-thread communication in C programs
                   URL:http://repo.hu/projects/cchan    port70.net      70
                   h[HTTP] Stutter (LISP interpreter)   URL:http://hactar.port70.net/stutter    port70.net      70
                   i    fake    (NULL)  0
                   1NECRON card game    necron  port70.net      70
                   1Gopherchan! chan    port70.net      70
                   i    fake    (NULL)  0
                   
RawContentLength : 818
```

### Gopher+ Metadata
You can use the `-Abstract` parameter to fetch Gopher+ information instead of the resource itself.

```powershell
PS C:\> Invoke-GopherRequest -Abstract gopher://colincogle.name/0downloads/pgp.txt | Format-List

INFO     : 0pgp.txt     /downloads/pgp.txt      colincogle.name 70      +
ADMIN    : {Admin: Colin Cogle <colin@colincogle.name>, Mod-Date: Sun Nov 28 14:37:30 2021 <20211128143730>}
VIEWS    : text/plain: <5k>
ABSTRACT : Colin Cogle's PGP keys and signing policy.
```

### Downloading Files
Finally, you can also use PSGopher's `-OutFile` parameter to download files:

```powershell
PS /Users/colin> Invoke-GopherRequest -UseSSL gopher://colincogle.name/0downloads/pgp.txt -OutFile pgp.txt
PS /Users/colin> Get-Item pgp.txt                            

    Directory: /Users/colin

UnixMode   User             Group                 LastWriteTime           Size Name
--------   ----             -----                 -------------           ---- ----
-rw-r--r-- colin            wheel                2/8/2022 08:05           5218 pgp.txt
```

Enjoy Gopherspace!

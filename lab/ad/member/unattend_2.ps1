#requires -Version 5.1
$ErrorActionPreference = 'Stop'

# install latest powershell
Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"

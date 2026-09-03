#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-PSDebug -Trace 1

# install latest powershell
Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI"

Write-Host "STEP PWSH DONE"
exit 0

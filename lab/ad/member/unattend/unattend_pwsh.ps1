#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-PSDebug -Trace 1

Start-Transcript -Path "C:\Windows\Temp\unattend_pwsh.log"

# install latest powershell
Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"

Stop-Transcript

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-PSDebug -Trace 1

Write-Host "[UNATTEND] STEP BEGIN: PWSH (1)"

# install latest powershell
Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"

Write-Host "[UNATTEND] STEP END: PWSH (1)"
exit 0

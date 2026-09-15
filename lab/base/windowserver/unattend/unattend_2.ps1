$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-PSDebug -Trace 1

Write-Host "[UNATTEND] STEP BEGIN: 2"

function step_pwsh {
    # install latest powershell
    Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"
}

step_pwsh

Write-Host "[UNATTEND] STEP END: 2"
exit 0

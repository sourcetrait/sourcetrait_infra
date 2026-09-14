$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-PSDebug -Trace 1

Write-Host "[UNATTEND] STEP BEGIN: 2"

function read_img_json {
    Get-Content -LiteralPath 'E:\img.json' -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function step_nic {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$img
    )
    if ([string]::IsNullOrWhiteSpace($img.dhcp)) {
        return
    }
    
    ipconfig /setclassid '*' $img.dhcp
    ipconfig /release '*'
    ipconfig /renew '*'
}

function step_pwsh {
    # install latest powershell
    Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-powershell.ps1) } -UseMSI -Quiet"
}

$img = read_img_json
step_nic
step_pwsh

Write-Host "[UNATTEND] STEP END: 2"
exit 0

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-PSDebug -Trace 1

Write-Host "[UNATTEND] STEP BEGIN: 1"

function step_virtio_drivers {
    $virtio_exits = @(
        0 # success
        3010 # success, reboot required
    )

    # install virtio drivers
    $p = Start-Process 'msiexec.exe' -ArgumentList '/i F:\virtio-win-gt-x64.msi /qn /norestart /l*v C:\Windows\Temp\unattend_virtio_drivers.log' -Wait -PassThru
    if ($p.ExitCode -notin $virtio_exits) {
        throw '[UNATTEND] ERROR Failed to install virtio drivers'
    }
}

step_virtio_drivers

Write-Host "[UNATTEND] STEP END: 1"
exit 0

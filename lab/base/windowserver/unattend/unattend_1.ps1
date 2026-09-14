$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-PSDebug -Trace 1

Write-Host "[UNATTEND] STEP BEGIN: 1"

function step_virtio {
    $virtio_exits = @(
        0 # success
        3010 # success, reboot required
    )

    # install the virtio drivers and the qemu guest agent from the attached iso
    $p = Start-Process 'F:\virtio-win-guest-tools.exe' -ArgumentList '/install /quiet /norestart /log C:\Windows\Temp\unattend_virtio.log' -Wait -PassThru
    if ($p.ExitCode -notin $virtio_exits) {
        throw '[UNATTEND] ERROR Failed to install virtio guest tools'
    }
}

step_virtio

Write-Host "[UNATTEND] STEP END: 1"
exit 0

#requires -Version 7
param(
    [Parameter(Mandatory)]
    [int]$step
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-PSDebug -Trace 1

function step_virtio {
    # install the virtio drivers and the qemu guest agent from the attached iso
    $p = Start-Process 'F:\virtio-win-guest-tools.exe' -ArgumentList '/install /quiet /norestart /log C:\Windows\Temp\virtio_win.log' -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { exit 3 }
}

function step_update {
    # install updates
    Install-PSResource -Name PSWindowsUpdate -TrustRepository -Scope AllUsers
    Import-Module PSWindowsUpdate
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
}

function step_sshd {
    # install sshd
    Add-WindowsCapability -Online -Name OpenSSH.Server
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd

    # configure powershell as the default for ssh logins (replaced by nu later)
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'DefaultShell' -Value (Get-Command pwsh).Source
}

function step_disk {
    # disable recovery
    reagentc /disable

    # delete the recovery partition
    $recovery_partition = Get-Partition -DiskNumber 0 | Where-Object Type -eq 'Recovery'
    Remove-Partition -DiskNumber 0 -PartitionNumber $recovery_partition.PartitionNumber -Confirm:$false

    # reclaim space from the deleted recovery partition
    $size = Get-PartitionSupportedSize -DriveLetter C
    Resize-Partition -DriveLetter C -Size $size.SizeMax
}

function step_choco {
    # install choco
    Invoke-Expression (Invoke-RestMethod 'https://community.chocolatey.org/install.ps1')
}

function step_nushell {
    # install nushell
    $rel = Invoke-RestMethod 'https://api.github.com/repos/nushell/nushell/releases/latest'
    $url = ($rel.assets | Where-Object name -like 'nu-*-x86_64-pc-windows-msvc.msi').browser_download_url
    $dst = "$env:TEMP\nushell.msi"
    Invoke-WebRequest -Uri $url -OutFile $dst
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$dst`" ALLUSERS=1 /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -ne 0) { exit 3 }

}

$CHOCO_PACKAGES = @('git','helix')

function step_choco_packages {
    $PSNativeCommandUseErrorActionPreference = $false
    foreach ($pkg in $CHOCO_PACKAGES) {
        choco install $pkg -y
        "choco $pkg exit $LASTEXITCODE"
    }
}

function step_vs {
    # msvc linker and windows sdk from the latest stable build tools; rustup-init -y skips this offer
    Invoke-WebRequest 'https://aka.ms/vs/stable/vs_buildtools.exe' -OutFile "$env:TEMP\vs_BuildTools.exe"
    $p = Start-Process "$env:TEMP\vs_BuildTools.exe" -ArgumentList '--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended' -Wait -PassThru
    "vs exit $($p.ExitCode)"
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { exit 3 }
}

function step_rust {
    # toolchains shared under RUSTUP_HOME, proxies global, each user keeps the default cargo home
    [Environment]::SetEnvironmentVariable('RUSTUP_HOME', 'C:\ProgramData\rustup', 'Machine')
    $env:RUSTUP_HOME = 'C:\ProgramData\rustup'
    $env:CARGO_HOME = 'C:\ProgramData\cargo'
    Invoke-WebRequest 'https://win.rustup.rs/x86_64' -OutFile "$env:TEMP\rustup-init.exe"
    $p = Start-Process "$env:TEMP\rustup-init.exe" -ArgumentList '-y --no-modify-path --default-toolchain stable --profile default' -Wait -PassThru
    if ($p.ExitCode -ne 0) { exit 3 }
    & 'C:\ProgramData\cargo\bin\rustup.exe' set auto-self-update disable

    $path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    [Environment]::SetEnvironmentVariable('Path', $path.TrimEnd(';') + ';C:\ProgramData\cargo\bin', 'Machine')
}

function step_defender {
    # uninstall defender
    Uninstall-WindowsFeature -Name Windows-Defender -Remove
}

function step_net {
    # nla classifies the network on the first full boot; wait for the profile
    $deadline = (Get-Date).AddMinutes(2)
    while (-not (Get-NetConnectionProfile -ErrorAction SilentlyContinue)) {
        if ((Get-Date) -gt $deadline) { throw 'no network profile after timeout' }
        Start-Sleep 2
    }

    Set-NetConnectionProfile -NetworkCategory Private    # set network to private trust
}

function step_sconfig {
    # disable sconfig on startup
    powershell -NoProfile -Command 'Set-SConfig -AutoLaunch $false'
}

function step_logon_count {
    # windows adds one to LogonCount; zero it so the next boot needs a real logon
    reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' /v AutoLogonCount /t REG_DWORD /d 0 /f
}

function step_reboot {
    # end the build rebooted; the script's remaining lines run before the reboot lands
    shutdown /r /t 0
}

# step1: pwsh
switch ($step) {
    2 {
        step_update
    }
    3 {
        step_sshd
        step_disk
        step_defender
    }
    4 {
        step_choco
        step_nushell
    }
    111 {
       step_net
       step_virtio
       step_vs
       step_rust
       step_choco_packages
       step_sconfig
       step_logon_count
       step_reboot
    }
    default {
        Write-Error "Unknown step: $step"
        exit 3
    }
}

Write-Host "STEP $step DONE"
exit 0

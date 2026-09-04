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
    # setup sshd
    #Add-WindowsCapability -Online -Name OpenSSH.Server
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd

    # configure powershell as the default for ssh logins (replaced by nu later)
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'DefaultShell' -Value (Get-Command pwsh).Source

    $cfg = 'C:\ProgramData\ssh\sshd_config'
    $conf = Get-Content $cfg | Where-Object { $_ -notmatch '^\s*Match Group administrators' -and $_ -notmatch 'administrators_authorized_keys' }
    $conf = $conf -replace '^\s*AllowGroups .*', 'AllowGroups "openssh users"'
    @('PasswordAuthentication no', 'KbdInteractiveAuthentication no') + $conf | Set-Content $cfg -Encoding ascii
    Restart-Service sshd
}

function step_winre {
    # disable recovery
    $PSNativeCommandUseErrorActionPreference = $false
    reagentc /disable
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
        throw "Failed to disable WinRE: $LASTEXITCODE"
    }
}

function step_disk {
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


function step_user {
    param(
        [Parameter(Mandatory)]
        [string]$user
    )
    
    $USER_DIRS = @('.config','.sys\cache','.sys\data','.sys\state')

    # user's profile does not exist until a logon; force one, then lay down its .ssh
    $pw = ConvertTo-SecureString (Get-Content 'E:\dumb_password' -Raw).Trim() -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($user, $pw)
    Start-Process cmd.exe -ArgumentList '/c exit' -Credential $cred -LoadUserProfile -WindowStyle Hidden -Wait

    foreach ($d in $USER_DIRS) {
        New-Item -ItemType Directory (Join-Path "C:\Users\$user" $d) -Force
    }

    icacls.exe "C:\Users\$user\.config" /setowner $user /t /c
    icacls.exe "C:\Users\$user\.sys" /setowner $user /t /c

    $ssh = "C:\Users\$user\.ssh"
    Copy-Item 'E:\.ssh' $ssh -Recurse
    Get-ChildItem $ssh -Recurse -File | ForEach-Object { $_.IsReadOnly = ($_.Name -ne 'authorized_keys') }
    icacls.exe $ssh /setowner $user /t /c
    icacls.exe $ssh /inheritance:r /grant "${user}:(OI)(CI)F" /grant 'SYSTEM:(OI)(CI)F'
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

function step_ngen {
    # compile the queued .net framework native images now, so the built system idles
    foreach ($root in 'Framework64', 'Framework') {
        $ngen = Get-ChildItem "$env:windir\Microsoft.NET\$root\v*\ngen.exe" | Sort-Object { [version]$_.Directory.Name.TrimStart('v') } | Select-Object -Last 1
        & $ngen.FullName executeQueuedItems
    }
}

function step_logon_count {
    # windows adds one to LogonCount; zero it so the next boot needs a real logon
    reg add 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' /v AutoLogonCount /t REG_DWORD /d 0 /f
}

function step_reboot {
    # end the build rebooted; the script's remaining lines run before the reboot lands
    shutdown /r /t 0
}

function step_default_profile {
    # new users get ~\.cargo\bin on their own path, via the default profile hive
    reg.exe load 'HKU\DefaultUser' 'C:\Users\Default\NTUSER.DAT'
    # PATH
    reg.exe add 'HKU\DefaultUser\Environment' /v Path /t REG_EXPAND_SZ /d '%USERPROFILE%\AppData\Local\Microsoft\WindowsApps;%USERPROFILE%\.cargo\bin' /f
    # XDG_CONFIG_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_CONFIG_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\.config' /f
    # XDG_CACHE_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_CACHE_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\.sys\cache' /f
    # XDG_DATA_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_DATA_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\.sys\data' /f
    # XDG_STATE_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_STATE_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\.sys\state' /f
    # UENV_USR_SPEC
    reg.exe add 'HKU\DefaultUser\Environment' /v UENV_USR_SPEC /t REG_SZ /d 'dotsys' /f
    # CARGO_TARGET_DIR
    reg.exe add 'HKU\DefaultUser\Environment' /v CARGO_TARGET_DIR /t REG_EXPAND_SZ /d '%USERPROFILE%\.sys\cache\cargo\target' /f
    reg.exe unload 'HKU\DefaultUser'
}

# step1: pwsh
switch ($step) {
    2 {
        step_sshd
        step_winre
        step_disk
        step_defender
        step_default_profile
    }
    3 {
        step_choco
        step_nushell
    }
    111 {
       step_update
       step_net
       step_virtio
       step_user 'lab'
       step_vs
       step_rust
       step_choco_packages
       step_sconfig
       step_ngen
       step_winre
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

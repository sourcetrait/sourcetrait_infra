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


function step_user_usrlay {
    param(
        [Parameter(Mandatory)]
        [string]$user
    )
    
    # user's profile does not exist until a logon; force one, then lay down its .ssh
    $pw = ConvertTo-SecureString (Get-Content 'E:\dumb_password' -Raw).Trim() -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($user, $pw)
    Start-Process cmd.exe -ArgumentList '/c exit' -Credential $cred -LoadUserProfile -WindowStyle Hidden -Wait

    $HOME_DIRS = @('.config','.sys','ai','bak','cab','data','doc','down','img','mdl','mnt','proj','repo','snd','sync','tmp','tpl','txt','vid','web')
    $SYS_DIRS = @('cache','data','state','desk','local','bak','mnt','my','of','secret','srv')
    $SYS_NU_DIRS = @('bin','mod')
    $LOCAL_DIRS = @('bin','etc','lib','opt','var','share','src','doc')
    $SECRET_DIRS = @('cache','data','state','my')
    $SRV_DIRS = @('git')
    $MY_SYS_DIRS = @('exe','cfg','lib','asset','data','doc','pkg','src')
    $MIX_DIRS = @('img/wall','img/pic','img/screen','img/scan','snd/music','vid/movie','txt/book','txt/paper','txt/guide','txt/ref','web/site','web/page','web/shot')
    $TPL_DIRS = @('img','snd','vid','mdl','ai','data','doc','proj','repo','cab')

    $DIRS = $HOME_DIRS +
        ($SYS_DIRS | ForEach-Object { ".sys\$_" }) +
        ($SYS_NU_DIRS | ForEach-Object { ".sys\of\nu\$_" }) +
        ($LOCAL_DIRS | ForEach-Object { ".sys\local\$_" }) +
        ($SECRET_DIRS | ForEach-Object { ".sys\secret\$_" }) +
        ($SRV_DIRS | ForEach-Object { ".sys\srv\$_" }) +
        ($MY_SYS_DIRS | ForEach-Object { ".sys\my\$_" }) +
        $MIX_DIRS +
        ($TPL_DIRS | ForEach-Object { "tpl\$_" })

    foreach ($d in $DIRS) {
        New-Item -ItemType Directory (Join-Path "C:\Users\$user" $d) -Force
    }

    # setup config
    $config = "C:\Users\$user\.config"
    Copy-Item 'E:\config\*' $config -Recurse

    # setup nushell
    Copy-Item "$config\nushell\config.usrlay.nu" "$config\nushell\config.nu"
    New-Item -ItemType SymbolicLink -Path "$config\nushell\scripts" -Target "C:\Users\$user\.sys\of\nu\mod"
    register_nu_plugins $cred $user

    # setup helix (doesn't honor xdg config)
    New-Item -ItemType SymbolicLink -Path "C:\Users\$user\AppData\Roaming\helix" -Target "$config\helix"

    foreach ($d in $HOME_DIRS) {
        icacls.exe "C:\Users\$user\$d" /setowner $user /t /c
    }

    # setup ssh
    $ssh = "C:\Users\$user\.ssh"
    Copy-Item 'E:\.ssh' $ssh -Recurse
    Get-ChildItem $ssh -Recurse -File | ForEach-Object { $_.IsReadOnly = ($_.Name -ne 'authorized_keys') }
    icacls.exe $ssh /setowner $user /t /c
    icacls.exe $ssh /inheritance:r /grant "${user}:(OI)(CI)F" /grant 'SYSTEM:(OI)(CI)F'
}

function register_nu_plugins {
    param(
      [Parameter(Mandatory)]
      [System.Management.Automation.PSCredential]$cred,

      [Parameter(Mandatory)]
      [string]$user
    )

    $user_root = Join-Path 'C:\Users' $user
    $nu_dir = 'C:\Program Files\nu\bin'
    $nu = Join-Path $nu_dir 'nu.exe'
    $plugin_registry = Join-Path $user_root '.config\nushell\plugin.msgpackz'

    $plugins = @(
      Get-ChildItem $nu_dir -Filter 'nu_plugin_*.exe' -File |
          Sort-Object Name
    )

    if ($plugins.Count -eq 0) {
      throw "No Nushell plugins found in $nu_dir"
    }

    $run_id = [guid]::NewGuid().ToString('N')
    $temporary_dir = Join-Path $user_root 'tmp'
    $plugin_script = Join-Path $temporary_dir "register-plugins-$run_id.nu"
    $plugin_stdout = Join-Path $temporary_dir "register-plugins-$run_id.stdout"
    $plugin_stderr = Join-Path $temporary_dir "register-plugins-$run_id.stderr"

    $plugin_lines = foreach ($plugin in $plugins) {
      $plugin_literal = ConvertTo-Json -InputObject $plugin.FullName -Compress
      "plugin add $plugin_literal"
    }

    $plugin_lines | Set-Content $plugin_script -Encoding utf8

    try {
      $p = Start-Process `
          -FilePath $nu `
          -ArgumentList @(
              '--plugin-config',
              "`"$plugin_registry`"",
              "`"$plugin_script`""
          ) `
          -Credential $cred `
          -LoadUserProfile `
          -WorkingDirectory $user_root `
          -WindowStyle Hidden `
          -RedirectStandardOutput $plugin_stdout `
          -RedirectStandardError $plugin_stderr `
          -Wait `
          -PassThru

      if ($p.ExitCode -ne 0) {
          $detail = if (Test-Path $plugin_stderr) {
              Get-Content $plugin_stderr -Raw
          }

          throw "Nushell plugin registration failed ($($p.ExitCode)): $detail"
      }

      Write-Host "Registered $($plugins.Count) Nushell plugins for $user"
    }
    finally {
      Remove-Item -LiteralPath @(
          $plugin_script,
          $plugin_stdout,
          $plugin_stderr
      ) -Force -ErrorAction SilentlyContinue
    }
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
    reg.exe load 'HKU\DefaultUser' 'C:\Users\Default\NTUSER.DAT'

    # PATH
    reg.exe add 'HKU\DefaultUser\Environment' /v Path /t REG_EXPAND_SZ /d '%USERPROFILE%\AppData\Local\Microsoft\WindowsApps;%USERPROFILE%\.sys\of\cargo\bin' /f

    # XDG_CONFIG_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_CONFIG_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\.config' /f
    # XDG_CACHE_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_CACHE_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\.sys\cache' /f
    # XDG_DATA_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_DATA_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\.sys\data' /f
    # XDG_STATE_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_STATE_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\.sys\state' /f

    # UENV_USR_SPEC
    reg.exe add 'HKU\DefaultUser\Environment' /v UENV_USR_SPEC /t REG_SZ /d 'usrlay' /f

    # CARGO_TARGET_DIR
    reg.exe add 'HKU\DefaultUser\Environment' /v CARGO_TARGET_DIR /t REG_EXPAND_SZ /d '%USERPROFILE%\.sys\cache\cargo\target' /f
    # CARGO_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v CARGO_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\.sys\of\cargo' /f

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
       step_user_usrlay 'lab'
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

#requires -Version 7
param(
    [Parameter(Mandatory)]
    [int]$step
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-PSDebug -Trace 1

# Log lines:
# - '[UNATTEND] STEP BEGIN' 
# - '[UNATTEND] STEP END'
# - '[UNATTEND] SKIP' Something was skipped by configuration, typically 'skip'
# - '[UNATTEND] ERROR'
# - '[UNATTEND] ERROR STEP UNKNOWN' Unlikely to occur
#
# Handling:
# - xml redirects all output to C:\Windows\Temp\unattend_{$step}.log
# - break early. throw errors to break; they'll be logged.
# - tracing does most of the logging work. manual on-success logging is usually unnecessary.
# - to manually react to exit codes, temporarily set `$PSNativeCommandUseErrorActionPreference = $false`
#   - otherwise, non-zero will break as intended by `$ErrorActionPreference = 'Stop'`
# - post-install testing will ensure everything was set up correctly
# - post-install cleanup will delete unattend logs and unmount iso drives
#
# Infra Development:
# - use '--skip' from infra.nu to disable heavy operations like windows updates and manual pre-compilation
#
# Drives:
# - 'C:' root
# - 'D:' windows.iso
# - 'E:' unattend.iso
# - 'F:' virtio.iso
#
# Step Ordering:
# 1. virtio driver install
# 2. latest PowerShell install. this script relies on it.
# 3-99. specialize pass; hardware / image. synchronous, in order.
#       some integral services and environment are not fully available.
#       reboot stepping is available; xml uses WillReboot. resumes at next step.
# 100+. out-of-box-experience (oobe) system pass; first-logon.
#       effectively asynchronous and unordered.
#       reboot stepping is unavailable.
#       integral services and environment are available.
#       xml users exist.

function read_img_json {
    Get-Content -LiteralPath 'E:\img.json' -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function log_skip {
    param(
        [Parameter(Mandatory)]
        [string]$skipped
    )

    Write-Host "[UNATTEND] SKIP Skipped: $skipped"
}

function step_update {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$img
    )

    if ($img.skip) {
        log_skip 'step_update'
        return
    }
    
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
    $winre_exits = @(
        0 # success
        2 # tolerate, file not found; winre config may not exist 
    )

    # disable recovery
    $PSNativeCommandUseErrorActionPreference = $false
    reagentc /disable
    if ($LASTEXITCODE -notin $winre_exits) {
        throw "[UNATTEND] ERROR Failed to disable WinRE: exit($LASTEXITCODE)"
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

function step_virtio_tools {
    $virtio_exits = @(
        0 # success
        3010 # success, reboot required
    )

    # install the virtio drivers and the qemu guest agent from the attached iso
    $p = Start-Process 'F:\virtio-win-guest-tools.exe' -ArgumentList '/install /quiet /norestart /log C:\Windows\Temp\unattend_virtio_tools.log' -Wait -PassThru
    if ($p.ExitCode -notin $virtio_exits) {
        throw '[UNATTEND] ERROR Failed to install virtio guest tools'
    }
}

function step_choco {
    # install choco
    Invoke-Expression (Invoke-RestMethod 'https://community.chocolatey.org/install.ps1')
}

function step_nushell {
    $nu_exits = @(
        0 # success
        3010 # success, reboot required
    )
    
    # install nushell
    $rel = Invoke-RestMethod 'https://api.github.com/repos/nushell/nushell/releases/latest'
    $url = ($rel.assets | Where-Object name -like 'nu-*-x86_64-pc-windows-msvc.msi').browser_download_url
    $dst = "$env:TEMP\nushell.msi"
    Invoke-WebRequest -Uri $url -OutFile $dst
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$dst`" ALLUSERS=1 /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -notin $nu_exits) {
        throw '[UNATTEND] ERROR Failed to install Nushell'
    }
}

$CHOCO_PACKAGES = @('git','helix')

function step_choco_packages {
    $choco_exits = @(
        0 # success
        1641 # success, reboot initiated
        3010 # success, reboot required
    )
    
    foreach ($pkg in $CHOCO_PACKAGES) {
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            choco install $pkg --yes --no-progress
            $exitcode = $LASTEXITCODE
        } finally {
            $PSNativeCommandUseErrorActionPreference = $true
        }
        if ($exitcode -notin $choco_exits) {
            throw "[UNATTEND] ERROR Chocolatey failed to install: $pkg"
        }
    }
}

function step_vs {
    $vs_exits = @(
        0 # success
        3010 # success, reboot required
    )

    # msvc linker and windows sdk from the latest stable build tools; rustup-init -y skips this offer
    Invoke-WebRequest 'https://aka.ms/vs/stable/vs_buildtools.exe' -OutFile "$env:TEMP\vs_BuildTools.exe"
    $p = Start-Process "$env:TEMP\vs_BuildTools.exe" -ArgumentList '--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended' -Wait -PassThru
    if ($p.ExitCode -notin $vs_exits) {
        throw '[UNATTEND] ERROR Failed to install VisualStudio build tools'
    }
}

function step_rust {
    # toolchains shared under RUSTUP_HOME, proxies global, each user keeps the default cargo home
    [Environment]::SetEnvironmentVariable('RUSTUP_HOME', 'C:\ProgramData\rustup', 'Machine')
    $env:RUSTUP_HOME = 'C:\ProgramData\rustup'
    $env:CARGO_HOME = 'C:\ProgramData\cargo'
    Invoke-WebRequest 'https://win.rustup.rs/x86_64' -OutFile "$env:TEMP\rustup-init.exe"

    $p = Start-Process "$env:TEMP\rustup-init.exe" -ArgumentList '-y --no-modify-path --default-toolchain stable --profile default --component rust-analyzer' -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        throw "[UNATTEND] ERROR Failed to install Rust"
    }

    & 'C:\ProgramData\cargo\bin\rustup.exe' set auto-self-update disable

    $path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    [Environment]::SetEnvironmentVariable('Path', $path.TrimEnd(';') + ';C:\ProgramData\cargo\bin', 'Machine')
}


function step_user_pwrusr {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$img,

        [Parameter(Mandatory)]
        [string]$user
    )
    
    # user's profile does not exist until a logon; force one, then lay down its .ssh
    $pw = ConvertTo-SecureString $img.dumb_password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($user, $pw)
    Start-Process cmd.exe -ArgumentList '/c exit' -Credential $cred -LoadUserProfile -WindowStyle Hidden -Wait

    # disable password expiry
    Set-LocalUser -Name $user -PasswordNeverExpires $true

    & E:\pwrusr\shells\powershell\mkpwrhome.ps1 "C:\Users\$user"

    # setup config using pwrusr assets
    $config = "C:\Users\$user\.config"
    Copy-Item 'E:\pwrusr\config\*' $config -Recurse

    Get-ChildItem -LiteralPath $config -Recurse -Force -File |
        ForEach-Object { $_.IsReadOnly = $false }

    # setup nushell
    register_nu_plugins $cred $user

    # setup helix. doesn't honor xdg config, so symlink it
    New-Item -ItemType SymbolicLink -Path "C:\Users\$user\AppData\Roaming\helix" -Target "$config\helix"

    # setup ssh
    $ssh = "C:\Users\$user\.ssh"
    Copy-Item 'E:\.ssh\*' $ssh -Recurse
    Get-ChildItem -LiteralPath $ssh -Recurse -Force -File |
        ForEach-Object { $_.IsReadOnly = ($_.Name -like 'id_*') }
        
    & E:\pwrusr\shells\powershell\ownpwrhome.ps1 "C:\Users\$user" $user
}

function register_nu_plugins {
    param(
      [Parameter(Mandatory)]
      [System.Management.Automation.PSCredential]$cred,

      [Parameter(Mandatory)]
      [string]$user
    )

    $user_root = "C:\Users\$user"
    $nu_dir = 'C:\Program Files\nu\bin'
    $nu = "$nu_dir\nu.exe"
    $plugin_registry = "$user_root\.config\nushell\plugin.msgpackz"

    # collect standard plugins
    $plugins = @(
        Get-ChildItem -File -Filter 'nu_plugin_*.exe' $nu_dir
        | Sort-Object Name
    )
    if ($plugins.Count -eq 0) {
        throw "[UNATTEND] ERROR Nushell plugins not found in: $nu_dir"
    }

    # collect plugins from the pwrusr location, recursively
    $plugins += @(
        Get-ChildItem -File -Recurse -Filter 'nu_plugin_*.exe' "C:\Users\$user\sys\of\nu\plugins"
        | Sort-Object Name
    )

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

          throw "[UNATTEND] ERROR Nushell plugin registration failed: ($($p.ExitCode)) : $detail"
      }
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
        if ((Get-Date) -gt $deadline) {
            throw '[UNATTEND] ERROR Network profile not found after timeout'
        }
        Start-Sleep 2
    }

    Set-NetConnectionProfile -NetworkCategory Private    # set network to private trust
}

function step_sconfig {
    # disable sconfig on startup
    powershell -NoProfile -Command 'Set-SConfig -AutoLaunch $false -AllUsers'
}

function step_ngen {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$img
    )

    if ($img.skip) {
        log_skip 'step_ngen'
        return
    }

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
    reg.exe add 'HKU\DefaultUser\Environment' /v Path /t REG_EXPAND_SZ /d '%USERPROFILE%\AppData\Local\Microsoft\WindowsApps;%USERPROFILE%\sys\of\cargo\bin' /f

    # XDG_CONFIG_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_CONFIG_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\.config' /f
    # XDG_CACHE_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_CACHE_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\sys\cache' /f
    # XDG_DATA_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_DATA_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\sys\data' /f
    # XDG_STATE_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v XDG_STATE_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\sys\state' /f

    # UENV_USR_SPEC
    reg.exe add 'HKU\DefaultUser\Environment' /v UENV_USR_SPEC /t REG_SZ /d 'pwrusr' /f

    # CARGO_TARGET_DIR
    reg.exe add 'HKU\DefaultUser\Environment' /v CARGO_TARGET_DIR /t REG_EXPAND_SZ /d '%USERPROFILE%\sys\cache\cargo\target' /f
    # CARGO_HOME
    reg.exe add 'HKU\DefaultUser\Environment' /v CARGO_HOME /t REG_EXPAND_SZ /d '%USERPROFILE%\sys\of\cargo' /f

    reg.exe unload 'HKU\DefaultUser'
}

function step_password_policy {
    $PSNativeCommandUseErrorActionPreference = $false

    & net.exe accounts /maxpwage:unlimited
    if ($LASTEXITCODE -ne 0) {
        throw '[UNATTEND] ERROR Failed to disable local password expiration'
    }

    Set-LocalUser -Name 'Administrator' -PasswordNeverExpires $true
}

# main
Write-Host "[UNATTEND] STEP BEGIN: $step"
$img = read_img_json
switch ($step) {
    3 {
        step_sshd
        step_winre
        step_disk
        step_defender
        step_default_profile
        step_password_policy
    }
    4 {
        step_choco
        step_nushell
    }
    111 {
       step_update $img
       step_net
       step_virtio_tools
       step_user_pwrusr $img 'lab'
       step_vs
       step_rust
       step_choco_packages
       step_sconfig
       step_ngen $img
       step_winre
       step_logon_count
       step_reboot
    }
    default {
        throw "[UNATTEND] ERROR STEP UNKNOWN: $step"
    }
}

Write-Host "[UNATTEND] STEP END: $step"
exit 0

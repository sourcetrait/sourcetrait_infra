#requires -Version 7
param(
    [Parameter(Mandatory)]
    [int]$step
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-PSDebug -Trace 1

# wait for the network adapter (nla service) to come online
function wait_net {
    if ((Get-Service NlaSvc).Status -ne 'Running') {
        Start-Service NlaSvc
    }

    Start-Sleep 60
}

function step_update {
    # install updates
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name PSWindowsUpdate -Force -AllowClobber
    Import-Module PSWindowsUpdate
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
}

function step_net {
    # set network to private trust
    Set-NetConnectionProfile -NetworkCategory Private
}

function step_sshd {
    # install sshd
    Add-WindowsCapability -Online -Name OpenSSH.Server
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd

    # configure powershell as the default for ssh logins (replaced by nu later)
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'DefaultShell' -Value (Get-Command pwsh).Source -PropertyType String -Force | Out-Null
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
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

function step_nushell {
    # install nushell
    $rel = Invoke-RestMethod 'https://api.github.com/repos/nushell/nushell/releases/latest'
    $url = ($rel.assets | Where-Object name -like 'nu-*-x86_64-pc-windows-msvc.msi').browser_download_url
    $dst = "$env:TEMP\nushell.msi"
    Invoke-WebRequest -Uri $url -OutFile $dst
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$dst`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -ne 0) { exit 3 }

}

function step_nushell_default {
    # configure nushell as the default for ssh logins
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'DefaultShell' -Value (Get-Command nu).Source -PropertyType String -Force | Out-Null
}

function step_choco_packages {
    # install choco packages
    choco install git helix -y
}

function step_defender {
    # uninstall defender
    Uninstall-WindowsFeature -Name Windows-Defender -Remove
}

function step_sconfig {
    # disable sconfig on startup
    Set-SConfig -AutoLaunch $false
}

# step1: pwsh
switch ($step) {
    2 {
        step_update
    }
    3 {
        step_sshd
        step_disk
        step_net
    }
    4 {
        step_choco
        step_nushell
    }
    5 {
        step_nushell_default
        step_choco_packages
        step_defender
        step_sconfig
    }
    default {
        Write-Error "Unknown step: $step"
        exit 3
    }
}

exit 0

#requires -Version 7
param(
    [Parameter(Mandatory)]
    [int]$step
)
$ErrorActionPreference = 'Stop'

function step_3 {
    # set network to private trust
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private

    # install sshd
    Add-WindowsCapability -Online -Name OpenSSH.Server
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd

    # configure powershell as the default for ssh logins (replaced by nu later)
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'DefaultShell' -Value (Get-Command pwsh).Source -PropertyType String -Force | Out-Null

    # disable recovery
    reagentc /disable

    # delete the recovery partition
    $recovery_partition = Get-Partition -DiskNumber 0 | Where-Object Type -eq 'Recovery'
    Remove-Partition -DiskNumber 0 -PartitionNumber $recovery_partition.PartitionNumber -Confirm:$false

    # reclaim space from the deleted recovery partition
    $size = Get-PartitionSupportedSize -DriveLetter C
    Resize-Partition -DriveLetter C -Size $size.SizeMax
}

function step_4 {
    # install choco
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # install nushell
    $rel = Invoke-RestMethod 'https://api.github.com/repos/nushell/nushell/releases/latest'
    $url = ($rel.assets | Where-Object name -like 'nu-*-x86_64-pc-windows-msvc.msi').browser_download_url
    $dst = "$env:TEMP\nushell.msi"
    Invoke-WebRequest -Uri $url -OutFile $dst
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$dst`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -ne 0) { exit 3 }
}

function step_5 {
    # configure nushell as the default for ssh logins
    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'DefaultShell' -Value (Get-Command nu).Source -PropertyType String -Force | Out-Null

    # install choco packages
    choco install git helix -y

    # uninstall defender
    Uninstall-WindowsFeature -Name Windows-Defender -Remove
}

switch ($step) {
    3 { step_3 }
    4 { step_4 }
    5 { step_5 }
    default {
        Write-Error "Unknown step: $step"
        exit 3
    }
}

exit 0

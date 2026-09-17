const DIR_SELF: directory = path self .
const WINDOWS_ISO: path = 'windows_server_2025.noprompt.iso'
const VIRTIO_WIN_ISO: path = 'virtio-win.iso'

export def build [
    state: record
    img: record
    dry: bool = false
    debug: bool = false
]: nothing -> nothing {
    let unattend_iso = build_unattend $state $img
    let disk = $state.path.vm.disk_dir | path join $"($img.name).qcow2" | path expand
    let windows_iso = $state.path.vm.iso_dir | path join $WINDOWS_ISO
    let virtio_iso = $state.path.vm.iso_dir | path join $VIRTIO_WIN_ISO

    let ui_cmd = match $debug {
        false => "
            --graphics none
            --video none
            --autoconsole text
            --wait -1
        "
        true => "
            --graphics spice,listen=127.0.0.1
            --video qxl
            --input tablet,bus=usb
        "
    }

    let debug_cmd = match $dry {
        false => '',
        true => "
            --dry-run
            --print-xml
        "
    }
    
    let cmd = $"\(
    virt-install
        --name ($img.name)
        --memory 32768
        --vcpus 16
        --os-variant win2k25
        --disk format=qcow2,size=260,bus=sata,path=($disk)
        --cdrom ($windows_iso)
        --disk device=cdrom,bus=sata,path=($unattend_iso)
        --disk device=cdrom,bus=sata,path=($virtio_iso)
        --network model=virtio,network=($img.network)
        --sound none
        --controller type=virtio-serial
        --serial pty
        --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0
        --memballoon virtio
        --boot uefi,hd,cdrom
        ($ui_cmd)
        ($debug_cmd)
    )"

    nu -c $cmd
}

def dry_unattend [state: record, img: record]: nothing -> string {
    open ($DIR_SELF | path join 'autounattend.xml.liquid')
    | str soak $img
}

export def build_unattend [state: record, img: record, dry: bool = false, debug: bool = false]: nothing -> path {
    if $dry {
        return (dry_unattend $state $img)
    }
    
    let tmp_dir = (mktemp -d .infra-unattend.XXXXXX)
    let target_dir = ($tmp_dir | path join 'target')
    let ssh_dir = ($target_dir | path join '.ssh')
    let iso_file = ($tmp_dir | path join 'unattend.iso')
    mkdir $target_dir

    mkdir $ssh_dir
    chown ($env.USER):($env.USER) $ssh_dir
    chmod -R 700 $ssh_dir

    # generate xml
    #open ($DIR_SELF | path join 'autounattend.xml.liquid')
    #| str soak $img
    #| save ($target_dir | path join 'autounattend.xml')
    $img | soak dir ($DIR_SELF | path join 'autounattend') $target_dir

    # generate img.json
    {
        dumb_password: $state.cfg.dumb_password
        skip: $state.skip
    }
    | to json
    | save ($target_dir | path join 'img.json')

    # copy pwrusr config assets
    git checkout-index
    cp -r ($state.path.pwrusr_repo | path join 'config') ($target_dir | path join 'config')
    # copy unattended assets
    cp -r ($DIR_SELF | path join 'unattend' '*' | into glob) $target_dir

    # copy keys
    for lab_login in $state.path.key.lab_logins {
    cp $lab_login $ssh_dir
        open --raw $lab_login | save --append ($ssh_dir | path join 'authorized_keys')
    }
    
    cp $state.path.key.lab_dumb ($ssh_dir | path join 'id_lab_dumb')
    cp $state.path.key.lab_dumb_pub ($ssh_dir | path join 'id_lab_dumb.pub')
    chown -R ($env.USER):($env.USER) $ssh_dir
    chmod 400 ($"($ssh_dir)/*" | into glob)
    chmod 600 ($ssh_dir | path join 'authorized_keys')
    
    xorriso -as mkisofs -o $iso_file -V UNATTEND -J -r $target_dir
    
    let unattend_iso = ($state.path.vm.unattend_dir | path join $"($img.name).unattend.iso")
    mv $iso_file $unattend_iso
    chown ($env.USER):($state.group.vm) $unattend_iso
    chmod 660 $unattend_iso
    
    rm -rf $tmp_dir
    $unattend_iso
}

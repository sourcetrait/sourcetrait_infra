
export def build [state: record, img: record] {
  let unattend_iso = (build_unattend $state $img)
  (virt-install
    --name ($img.name)
    --memory 32768
    --vcpus 16
    --os-variant win2k25
    --disk path=/mnt/storage/kvm/disk/($img.name).qcow2,format=qcow2,size=260,bus=sata
    --cdrom /mnt/storage/kvm/iso/windows_server_2025_eval_noprompt.iso
    --disk path=($unattend_iso),device=cdrom,bus=sata
    --disk path=($state.path.vm.virtio_win_iso),device=cdrom,bus=sata
    --network network=default,model=e1000e
    --graphics spice,listen=127.0.0.1
    --video qxl
    --sound none
    --controller type=virtio-serial
    --input tablet,bus=usb
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0
    --memballoon virtio
    --boot uefi,hd,cdrom
  )
}

export def debug_build [state: record, img: record] {
  let unattend_iso = ($state.path.vm.unattend_dir | path join ($img.name) 'unattend.iso')
  (virt-install
    --name ($img.name)
    --memory 32768
    --vcpus 16
    --os-variant win2k25
    --disk path=/mnt/storage/kvm/disk/($img.name).qcow2,format=qcow2,size=260,bus=sata
    --cdrom /mnt/storage/kvm/iso/windows_server_2025_eval_noprompt.iso
    --disk path=($unattend_iso),device=cdrom,bus=sata
    --disk path=($state.path.vm.virtio_win_iso),device=cdrom,bus=sata
    --network network=default,model=e1000e
    --graphics spice,listen=127.0.0.1
    --video qxl
    --sound none
    --controller type=virtio-serial
    --input tablet,bus=usb
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0
    --memballoon virtio
    --boot uefi,hd,cdrom
    --dry-run
    --print-xml
  )
}

export def debug_unattend [state: record, img: record]: nothing -> string {
  const DIR_SELF: directory = path self .
  open ($DIR_SELF | path join 'autounattend.xml.liquid')
    | from grimoire liquid $img
}

export def build_unattend [state: record, img: record]: nothing -> path {
  const DIR_SELF: directory = path self .
  let tmp_dir = (mktemp -d .infra-unattend.XXXXXX)
  let target_dir = ($tmp_dir | path join 'target')
  let ssh_dir = ($target_dir | path join '.ssh')
  let iso_file = ($tmp_dir | path join 'unattend.iso')
  mkdir $target_dir

  mkdir $ssh_dir
  chown ($env.USER):($env.USER) $ssh_dir
  chmod -R 700 $ssh_dir

  # generate xml
  open ($DIR_SELF | path join 'autounattend.xml.liquid')
    | from grimoire liquid $img
    | save ($target_dir | path join 'autounattend.xml')

  # copy dumb_password
  $state.cfg.dumb_password | save ($target_dir | path join 'dumb_password')

  # copy unattended scripts
  cp ($DIR_SELF | path join 'unattend' | path join 'unattend_pwsh.ps1') $target_dir
  cp ($DIR_SELF | path join 'unattend' | path join 'unattend.ps1') $target_dir

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

  let unattend_dir = ($state.path.vm.unattend_dir | path join ($img.name))
  if not ($unattend_dir | path exists) {
    mkdir $unattend_dir
    chown ($env.USER):($state.group.vm) $unattend_dir
    chmod 770 $unattend_dir
  }

  let unattend_iso = ($unattend_dir | path join 'unattend.iso')
  let unattend_iso_link = ($state.path.vm.unattend_dir | path join $"($img.name)_unattend.iso")
  if ($unattend_iso_link | path exists) {
    rm $unattend_iso_link
  }
  
  mv $iso_file $unattend_iso
  chown ($env.USER):($state.group.vm) $unattend_iso
  chmod 660 $unattend_iso
  ( cd $state.path.vm.unattend_dir ; ln -s ($img.name | path join 'unattend.iso') $"($img.name)_unattend.iso" )
  chown ($env.USER):($state.group.vm) $unattend_iso_link
  chmod 660 $unattend_iso_link

  #rm -rf $tmp_dir
  $unattend_iso_link
}

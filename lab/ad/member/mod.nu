
export def build [state: record, name: string] {
  let unattend_iso = (build_unattend $state $name)
  (virt-install
    --name $name
    --memory 32768
    --vcpus 16
    --os-variant win2k25
    --disk path=/mnt/storage/kvm/disk/($name).qcow2,format=qcow2,size=260,bus=sata
    --cdrom /mnt/storage/kvm/iso/windows_server_2025_eval_noprompt.iso
    --disk path=($unattend_iso),device=cdrom,bus=sata
    --disk path=($state.path.virtio_win_iso),device=cdrom,bus=sata
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

export def debug_build [state: record, name: string] {
  let unattend_iso = ($state.path.unattend_dir | path join $name 'unattend.iso')
  (virt-install
    --name $name
    --memory 32768
    --vcpus 16
    --os-variant win2k25
    --disk path=/mnt/storage/kvm/disk/($name).qcow2,format=qcow2,size=260,bus=sata
    --cdrom /mnt/storage/kvm/iso/windows_server_2025_eval_noprompt.iso
    --disk path=($unattend_iso),device=cdrom,bus=sata
    --disk path=($state.path.virtio_win_iso),device=cdrom,bus=sata
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

export def debug_unattend [state: record, name: string]: nothing -> string {
  const DIR_SELF: directory = path self .
  open ($DIR_SELF | path join 'autounattend.xml.liquid')
    | from grimoire liquid { name: $name }
}

export def build_unattend [state: record, name: string]: nothing -> path {
  const DIR_SELF: directory = path self .
  let tmp_dir = (mktemp -d .infra-unattend.XXXXXX)
  let target_dir = ($tmp_dir | path join 'target')
  let iso_file = ($tmp_dir | path join 'unattend.iso')
  mkdir $target_dir
  open ($DIR_SELF | path join 'autounattend.xml.liquid')
    | from grimoire liquid { name: $name }
    | save ($target_dir | path join 'autounattend.xml')

  xorriso -as mkisofs -o $iso_file -V UNATTEND -J -r $target_dir

  let unattend_dir = ($state.path.unattend_dir | path join $name)
  if not ($unattend_dir | path exists) {
    mkdir $unattend_dir
    chown ($env.USER):($state.group.vm) $unattend_dir
    chmod 770 $unattend_dir
  }

  let unattend_iso = ($unattend_dir | path join 'unattend.iso')
  let unattend_iso_link = ($state.path.unattend_dir | path join $"($name)_unattend.iso")
  if ($unattend_iso_link | path exists) {
    rm $unattend_iso_link
  }
  
  mv $iso_file $unattend_iso
  chown ($env.USER):($state.group.vm) $unattend_iso
  chmod 660 $unattend_iso
  ( cd $state.path.unattend_dir ; ln -s ($name | path join 'unattend.iso') $"($name)_unattend.iso" )
  chown ($env.USER):($state.group.vm) $unattend_iso_link
  chmod 660 $unattend_iso_link

  #rm -rf $tmp_dir
  $unattend_iso_link
}

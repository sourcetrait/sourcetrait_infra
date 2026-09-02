#
# --features hyperv_relaxed=on,hyperv_vapic=on,hyperv_spinlocks=on,hyperv_spinlocks_retries=8191,vmport.state=off
export def build [state: record, name: string] {
  (virt-install
    --name $name
    --memory 32768
    --vcpus 16
    --os-variant win2k25
    --disk path=/mnt/storage/kvm/disk/($name).qcow2,format=qcow2,size=260,bus=sata
    --cdrom /mnt/storage/kvm/iso/windows_server_2025_eval.iso
    --network network=default,model=e1000e
    --graphics spice,listen=127.0.0.1
    --video qxl
    --sound none
    --controller type=virtio-serial
    --input tablet,bus=usb
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0
    --disk path=($state.paths.virtio_win_iso),device=cdrom,bus=sata
    --memballoon virtio
    --boot hd,cdrom
  )
}

export def debug_def [state: record, name: string]: nothing -> string {
  (virt-install
    --name $name
    --memory 32768
    --vcpus 16
    --os-variant win2k25
    --disk path=/mnt/storage/kvm/disk/($name).qcow2,format=qcow2,size=260,bus=sata
    --cdrom /mnt/storage/kvm/iso/windows_server_2025_eval.iso
    --network network=default,model=e1000e
    --graphics spice,listen=127.0.0.1
    --video qxl
    --sound none
    --controller type=virtio-serial
    --input tablet,bus=usb
    --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0
    --disk path=($state.paths.virtio_win_iso),device=cdrom,bus=sata
    --memballoon virtio
    --boot hd,cdrom
    --dry-run
    --print-xml
  )
}

export def debug_auto [state: record, name: string]: nothing -> string {
}

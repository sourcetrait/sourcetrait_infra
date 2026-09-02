
export def build [name: string] {
  (virt-install
    --name $name
    --memory 32768
    --vcpus 16
    --cpu host-passthrough
    --machine q35
    --os-variant win2k25
    --features hyperv_relaxed=on,hyperv_vapic=on,hyperv_spinlocks=on,hyperv_spinlocks_retries=8191,vmport.state=off
    --clock offset=localtime,rtc_tickpolicy=catchup,pit_tickpolicy=delay,hpet_present=no,hypervclock_present=yes
    --disk path=/mnt/storage/kvm/disk/($name).qcow2,format=qcow2,size=260,bus=sata
    --cdrom /mnt/storage/kvm/iso/windows_server_2025_eval.iso
    --network network=default,model=e1000e
    --graphics spice,listen=127.0.0.1
    --video qxl
    --sound ich9
    --controller type=virtio-serial
    --input tablet,bus=usb
    --watchdog itco,action=reset
    --memballoon virtio
    --boot hd,cdrom
  )
}

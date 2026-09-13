# NOTES

## Resolve VM names
This will resolve libvirt VM names (`virt-install --name`) as DNS names (qualified).
Note: Invalid hostnames = bad

### Debian
Install:
```bash
sudo apt install libnss-libvirt
```

Edit:
```
# /etc/nsswitch.conf
# edit: add 'libvirt_guest' after 'files' so that it resolves early
hosts:          files libvirt_guest mdns4_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] dns myhostname mymachines
```

Test:
```bash
# restart the vm
virsh shutdown $vm_name
virsh start $vm_name
# check resolution directly against the guest resolver
getent -s libvirt_guest ahostsv4 $vm_name
# should look something like:
# $vm_ip STREAM $vm_name
# $vm_ip DGRAM
# $vm_ip RAW
# check resolution normally
getent ahostsv4 $vm_name
# should look the same as above
# if not: ordering in the `hosts:` field is probably in play
ping $vm_name
# should ping if snmp is allowed
```
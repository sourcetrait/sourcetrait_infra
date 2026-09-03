#!/usr/bin/env nu

const LAB_AD_CONTROLLER: path = 'lab/ad/controller'
const LAB_AD_MEMBER: path = 'lab/ad/member'

export const BUILDS: list<path> = [
  $LAB_AD_CONTROLLER
  $LAB_AD_MEMBER
]

export def builds []: nothing -> list<path> { BUILDS }

def init [] {
  {
    path: {
      vm: {
        iso_dir: '/mnt/storage/kvm/iso'
        disk_dir: '/mnt/storage/kvm/disk'
        unattend_dir: '/mnt/storage/kvm/unattend'
        virtio_win_iso: '/mnt/storage/kvm/iso/virtio-win.iso'
      }
    },
    group: {
      vm: 'vmusr'
    },
  }
}

export def 'main debug build' [build: path@builds, cfg: record<hostname: string>] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init

  match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member
        member debug_build $state $cfg
    },
    _ => {
      error make $"not a build"
    },
  }
}

export def 'main debug unattend' [build: path@builds, cfg: record<hostname: string>] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init

  let xml = match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member
        member debug_unattend $state $cfg
    },
    _ => {
      error make $"not a build"
    },
  }

  print $xml
}

def make_cfg [hostname: string]: nothing -> record<hostname: string> {
  {
    hostname: $hostname
  }
}

export def 'main build' [build: path@builds, hostname: string] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init
  let cfg = make_cfg $hostname

  match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member 
        member build $state $cfg
    },
    _ => {
      error make $"not a build"
    },
  }
}

export def 'main build unattend' [build: path@builds, cfg: record<hostname: string>]: nothing -> path {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init

  let iso_file = match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member 
        member build_unattend $state $cfg
    },
    _ => {
      error make $"not a build"
    },
  }

  $iso_file
}

# Downloads the ISO if it isn't already in the ISO dir.
def setup_virtio_win_iso []: nothing -> nothing {
  const VIRTIO_WIN_ISO_FILENAME: path = 'virtio-win.iso'
  const VIRTIO_WIN_ISO_PATH: path = '/mnt/storage/kvm/iso/virtio-win.iso'
  const VIRTIO_WIN_ISO_URI: string = 'https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso'

  if ($VIRTIO_WIN_ISO_PATH | path exists) { return }

  let tmpdir = (mktemp -d .virtio-win-iso.XXXXXX)
  let tmpfile = ($tmpdir | path join $VIRTIO_WIN_ISO_FILENAME)
  try {
    http get $VIRTIO_WIN_ISO_URI | save ($tmpdir | path join $VIRTIO_WIN_ISO_FILENAME)
    mv $tmpfile $VIRTIO_WIN_ISO_PATH
  } finally {
    rm $tmpdir
  }
}

def setup_windowserver_iso []: nothing -> nothing {
  const WINDOWSERVER_ISO_LINK: path = '/mnt/storage/kvm/iso/windows_server_2025_eval.iso'
  const WINDOWSERVER_NOPROMPT_ISO: path = '/mnt/storage/kvm/iso/windows/server/2025/windows_server_2025_eval_noprompt.iso'
  const WINDOWSERVER_NOPROMPT_ISO_LINK: path = '/mnt/storage/kvm/iso/windows_server_2025_eval_noprompt.iso'

  if ($WINDOWSERVER_NOPROMPT_ISO | path exists) { return }

  let label = (blkid -s LABEL -o value $WINDOWSERVER_ISO_LINK)
  let tmpdir = (mktemp -d 'infra-setup.XXXXXX')
  let srcdir = ($tmpdir | path join 'src')
  let dstdir = ($tmpdir | path join 'dst')
  cd $tmpdir
  mkdir $srcdir $dstdir
  sudo mount -t udf $WINDOWSERVER_ISO_LINK $srcdir
  cp --recursive --all ($"($srcdir)/*" | into glob) $dstdir
  sudo umount $srcdir

  chmod -R u+w $dstdir
  cd ($dstdir | path join 'efi/microsoft/boot')
  mv 'efisys.bin' 'efisys.bin.old'
  mv 'efisys_noprompt.bin' 'efisys.bin'
  cd $tmpdir

  (genisoimage -o $WINDOWSERVER_NOPROMPT_ISO
    -udf -iso-level 3 -allow-limited-size
    -J -joliet-long -R -D -N -relaxed-filenames
    -V $"($label)"
    -b boot/etfsboot.com -no-emul-boot -boot-load-size 8 -boot-info-table
    -eltorito-alt-boot
    -e efi/microsoft/boot/efisys.bin -no-emul-boot
    $dstdir)

  if ($WINDOWSERVER_NOPROMPT_ISO_LINK | path exists) {
    rm $WINDOWSERVER_NOPROMPT_ISO_LINK
  }
  ( cd /mnt/storage/kvm/iso ; ln -s windows/server/2025/windows_server_2025_eval_noprompt2.iso )
  
  rm -rf $tmpdir
}

def 'main setup windows server' []: nothing -> nothing {
  sudo -v
  setup_windowserver_iso
  setup_virtio_win_iso
}

# do stuff
export def main [] { help infra }

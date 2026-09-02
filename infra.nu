#!/usr/bin/env nu

const LAB_AD_CONTROLLER: path = 'lab/ad/controller'
const LAB_AD_MEMBER: path = 'lab/ad/member'

export const BUILDS: list<path> = [
  $LAB_AD_CONTROLLER
  $LAB_AD_MEMBER
]

export def builds []: nothing -> list<path> { BUILDS }

def init [] {
  let virtio_win_iso: path = setup_virtio_win_iso
  {
    path: {
      virtio_win_iso: $virtio_win_iso,
      unattend_dir: '/mnt/storage/kvm/unattend'
    },
    group: {
      vm: 'vmusr'
    },
  }
}

export def 'main debug build' [build: path@builds, name: string] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init

  match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member
        member debug_build $state $name
    },
    _ => {
      error make $"not a build"
    },
  }
}

export def 'main debug unattend' [build: path@builds, name: string] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init

  let xml = match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member
        member debug_unattend $state $name
    },
    _ => {
      error make $"not a build"
    },
  }

  print $xml
}

export def 'main build' [build: path@builds, name: string] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init

  match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member 
        member build $state $name
    },
    _ => {
      error make $"not a build"
    },
  }
}

export def 'main build unattend' [build: path@builds, name: string]: nothing -> path {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init

  let iso_file = match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member 
        member build_unattend $state $name
    },
    _ => {
      error make $"not a build"
    },
  }

  $iso_file
}

# Downloads the ISO if it isn't already in the ISO dir.
def setup_virtio_win_iso []: nothing -> path {
  const VIRTIO_WIN_ISO_FILENAME: path = 'virtio-win.iso'
  const VIRTIO_WIN_ISO_PATH: path = '/mnt/storage/kvm/iso/virtio-win.iso'
  const VIRTIO_WIN_ISO_URI: string = 'https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso'

  if ($VIRTIO_WIN_ISO_PATH | path exists) { return $VIRTIO_WIN_ISO_PATH }
  let tmpdir = (mktemp -d .virtio-win-iso.XXXXXX)
  let tmpfile = ($tmpdir | path join $VIRTIO_WIN_ISO_FILENAME)
  try {
    http get $VIRTIO_WIN_ISO_URI | save ($tmpdir | path join $VIRTIO_WIN_ISO_FILENAME)
    mv $tmpfile $VIRTIO_WIN_ISO_PATH
  } finally {
    rm $tmpdir
  }

  if not ($VIRTIO_WIN_ISO_PATH | path exists) {
    error make $"Unable to setup virtio-win.iso"
  }

  $VIRTIO_WIN_ISO_PATH
}

# do stuff
export def main [] { help infra }

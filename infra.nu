#!/usr/bin/env nu

export const BUILDS: list<path> = [
  'lab/ad/kvm/controller'
  'lab/ad/kvm/member'
]

export def builds []: nothing -> list<path> { BUILDS }

export def 'main build' [build: path@builds, name: string] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init

  match $build {
    'lab/ad/kvm/member' => {
        overlay use --prefix ./lab/ad/kvm/member 
        member build $state $name
        overlay hide member
    },
    _ => {},
  }
}

def init [] {
  let virtio_win_iso: path = setup_virtio_win_iso
  {
    paths: {
      virtio_win_iso: $virtio_win_iso
    }
  }
}

export def 'main debug def' [build: path@builds, name: string] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init

  match $build {
    'lab/ad/kvm/member' => {
        overlay use --prefix ./lab/ad/kvm/member
        member debug_def $state $name
        overlay hide member
    },
    _ => {
      error make $"not a build"
    },
  }
}

export def 'main debug auto' [build: path@builds, name: string] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  let state = init

  match $build {
    'lab/ad/kvm/member' => {
        overlay use --prefix ./lab/ad/kvm/member
        member debug_auto $state $name
        overlay hide member
    },
    _ => {
      error make $"not a build"
    },
  }
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

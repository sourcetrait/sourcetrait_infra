#!/usr/bin/env nu

const LAB_AD_CONTROLLER: path = 'lab/ad/controller'
const LAB_AD_MEMBER: path = 'lab/ad/member'

export const BUILD_PATHS: list<path> = [
  $LAB_AD_CONTROLLER
  $LAB_AD_MEMBER
]

export const BUILDS: table<path: path, hostname: string, slug: string> = [
    [path                 hostname                   slug               ];
    ['lab/windowserver'   'windowserver.lab.infra'   'lab-windowserver' ]
    ['lab/ad/controller'  'controller.ad.lab.infra'  'lab-ad-controller']
    ['lab/ad/member'      'member.ad.lab.infra'      'lab-ad-member'    ]
]

export def builds []: nothing -> list<path> { BUILD_PATHS }

const CONFIG_DIRNAME: directory = 'sourcetrait/infra'
const INFRA_DIR: directory = path self .

def init [quick: bool = false] {
  let usrlay_repo = $INFRA_DIR | path join 'extern/usrlay'
  if not ($usrlay_repo | path join 'VERSION' | path exists) {
    error make $"extern/usrlay does not exist"
  }
  
  let config_home = $env | get -o XDG_CONFIG_HOME | default ($env.HOME | path join '.config')
  let config_dir = $config_home | path join $CONFIG_DIRNAME
  if not ($config_dir | path exists) {
    mkdir $config_dir
    cp ($INFRA_DIR | path join 'assets' 'default' 'config.toml') $config_dir
  }

  let cfg = open ($config_dir | path join 'config.toml')
  
  mut lab_login_pubkeys = []
  for lab_key in $cfg.key.lab_logins {
    let pubkey = ($cfg.key.home | path join $"($lab_key).pub" | path expand)
    if not ($pubkey | path exists) {
      error make $"lab login pub key does not exist: ($pubkey)"
    }

    $lab_login_pubkeys = $lab_login_pubkeys | append $pubkey
  }

  if ($lab_login_pubkeys | is-empty) {
    error make $"no lab login pubkeys configured"
  }
  
  # dumb keys exist so that there's at least one usable signing key available on startup; completely untrustable
  if not ($cfg.key.home | path join $cfg.key.lab_dumb | path exists) {
    error make $"dumb lab key does not exist: ($cfg.key.home | path join $cfg.key.lab_dumb)"
  } else if not ($cfg.key.home | path join $"($cfg.key.lab_dumb).pub" | path exists) {
    error make $"dumb lab pubkey does not exist: ($cfg.key.home | path join $"($cfg.key.lab_dumb).pub")"
  } 
  
  {
    path: {
      infra_dir: $INFRA_DIR
      usrlay_repo: $usrlay_repo
      vm: {
        iso_dir: '/mnt/storage/kvm/iso'
        disk_dir: '/mnt/storage/kvm/disk'
        unattend_dir: '/mnt/storage/kvm/unattend'
        virtio_win_iso: '/mnt/storage/kvm/iso/virtio-win.iso'
      },
      key: {
        lab_logins: $lab_login_pubkeys
        lab_dumb: ($cfg.key.home | path join $cfg.key.lab_dumb | path expand)
        lab_dumb_pub: ($cfg.key.home | path join $"($cfg.key.lab_dumb).pub" | path expand)
      }
    },
    group: {
      vm: 'vmusr'
    },
    cfg: $cfg,
    quick: $quick,
  }
}

def get_build [name: string@builds]: nothing -> record<path: path, hostname: string, slug: string> {
    $BUILDS | where path == $name | first
}

# a string name parameter can take two forms: hostname (foo.bar.infra) or slug (kebab-case)
# the final name is always the same as the hostname, as its resolved by nss
# slug is used for things such as netbios name (windows's computername)
# if a slug is provided, the hostname / name will be "($slug).infra"
# if a hostname is provided, the slug will be the reverse of the hostname, sans 'infra'
def make_img [build: string@builds, state: record, img: oneof<nothing,string,record>]: nothing -> record<name: string, hostname: string> {
    let build = get_build $build
    
    mut name: oneof<nothing,string> = null
    mut hostname: oneof<nothing,string> = null
    mut slug: oneof<nothing,string> = null
    
    let img = match ($img | describe) {
        'nothing' => {},
        'string' => {
            $name = $img | default -e null
            {}
        },
        _ => {
            # these three are required together
            $name = $img | get -o name | default -e null
            $hostname = $img | get -o hostname | default -e null
            $slug = $img | get -o slug | default -e null
            
            if $name != null or $hostname != null or $slug != null {
                if $name == null or $hostname == null or $slug == null {
                    error make --unspanned "image name, hostname, slug must be defined together or not at all"
                } else if not ($name | str ends-with '.infra') {
                    error make --unspanned $"image name is not a '.infra' hostname: ($name)"
                } else if not ($hostname | str ends-with '.infra') {
                    error make --unspanned $"image hostname is not a '.infra' hostname: ($hostname)"
                } else if not (($slug | str kebab-case) != $slug) {
                    error make --unspanned $"image slug is a valid slug: ($slug)"
                }
            }
        }
    }

    if $name == null {
        $name = $build.hostname
        $hostname = $build.hostname
        $slug = $build.slug
    } else if $hostname == null or $slug == null {
        if ($name | str ends-with '.infra') {
            $name = $name | str lowercase
            $hostname = $name
            $slug = $name
                | split row '.' | reverse | skip 1
                | str join '-' | str kebab-case
        } else {
            $slug = $name | str kebab-case
            if not $slug == $name {
                error make --unspanned $"image name is not a valid slug: ($name)"
            }
            
            $hostname = $"($name).infra"
        }
    }
  
  {
    name: $name
    hostname: $hostname
    slug: $slug
    dumb_password: $state.cfg.dumb_password
  }
}

export def 'main debug build' [build: path@builds, img: oneof<nothing,string,record> = null, --quick] {
  if not ($build in $BUILD_PATHS) {
    error make $"not a build"
  }

  let state = init $quick
  let img = make_img $build $state $img

  match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member
        member debug_build $state $img
    },
    _ => {
      error make $"not a build"
    },
  }
}

export def 'main debug unattend' [build: path@builds, img: oneof<nothing,string, record> = null, --quick] {
  if not ($build in $BUILD_PATHS) {
    error make $"not a build"
  }

  let state = init $quick
  let img = make_img $build $state $img

  let xml = match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member
        member debug_unattend $state $img
    },
    _ => {
      error make $"not a build"
    },
  }

  print $xml
}

export def 'main build' [build: path@builds, img: oneof<nothing,string, record> = null, --quick] {
  if not ($build in $BUILD_PATHS) {
    error make $"not a build"
  }

  let state = init $quick
  let img = make_img $build $state $img

  match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member 
        member build $state $img
    },
    _ => {
      error make $"not a build"
    },
  }
}

export def 'main build unattend' [build: path@builds, img: oneof<nothing,string,record> = null, --quick]: nothing -> path {
  if not ($build in $BUILD_PATHS) {
    error make $"not a build"
  }

  let state = init $quick
  let img = make_img $build $state $img

  let iso_file = match $build {
    $LAB_AD_MEMBER => {
        overlay use --prefix ./lab/ad/member 
        member build_unattend $state $img
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

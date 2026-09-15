#!/usr/bin/env nu

const INFRA_DIR: directory = path self .
const CONFIG_DIRNAME: directory = 'sourcetrait/infra'
const INETS: list<string> = [default test infra]

const BUILDS: table<namepath: path, hostname: string, subnet: list<string>> = [
    [ namepath             hostname        subnet   ];
    [ 'lab/windowserver'   'windowserver'  [lab]    ]
    [ 'lab/ad/controller'  'controller'    [ad lab] ]
    [ 'lab/ad/member'      'member'        [ad lab] ]
]
const PATH_LAB_WINDOWSERVER: directory = 'lab/windowserver'
const PATH_LAB_AD_CONTROLLER: directory = 'lab/ad/controller'
const PATH_LAB_AD_MEMBER: directory = 'lab/ad/member'

export def namepaths []: nothing -> list<path> {
    $BUILDS | get namepath 
}

def init [skip: bool = false] {
  let usrlay_repo = $INFRA_DIR | path join 'extern/usrlay'
  if not ($usrlay_repo | path join 'VERSION' | path exists) {
    error make $"extern/usrlay does not exist"
  }
  
  let config_home = $env | get -o XDG_CONFIG_HOME | default ($env.HOME | path join '.config')
  let config_dir = $config_home | path join $CONFIG_DIRNAME
  if not ($config_dir | path exists) {
    mkdir $config_dir
    cp ($INFRA_DIR | path join 'assets/xdg/config/config.toml' | path expand) $config_dir
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
    skip: $skip,
  }
}

def get_build [namepath: string@namepaths]: nothing -> record<namepath: path, hostname: string, subnet: list<string>> {
    $BUILDS | where namepath == $namepath | first
}

def err_exclusive_nick [] {
    error make --unspanned $"--nick and $in are mutually exclusive arguments"
}

def make_img [
    build: record,
    state: record,
    img: oneof<nothing,record> = null,
    inet: string = 'test',
    nick: oneof<nothing,string> = null
]: nothing -> record<namepath: path, name: string, hostname: string, domain: string, network: string, dumb_password: string> {
    mut out = {
      namepath: $build.namepath
      name: ($build.subnet | prepend $build.hostname | append $inet | str join '-')
      hostname: $build.hostname
      domain: ($build.subnet | append $inet | str join '.')
      network: (match $inet {
          'test' | 'infra' => ($build.subnet | append $inet | str join '-'),
          $other => $other
      })
      dumb_password: $state.cfg.dumb_password
    }

    if $nick != null {
        $out.name = $img | str kebab-case | default -e null
        if $out.name == null {
            error make --unspanned $"invalid nick: $(nick)"
        }

        $out.hostname = $nick
    } else if $img != null {
        $out = $out | merge $img
    }

    $out
}

export def 'main build' [
    namepath: path@namepaths,
    --nick: string, -n: string
    --inet: string = 'test', -i: string = 'test'
    --skip, -s
    --debug,
]: oneof<nothing,record> -> nothing {
    if $nick != null and $in != null { err_exclusive_nick }
    
    let build = get_build $namepath
    let state = init $skip
    let img = make_img $build $state $in $inet $nick
    
    match $namepath {
        $PATH_LAB_WINDOWSERVER => {
            overlay use --prefix ./lab/windowserver 
            windowserver build $state $img $debug
        },
        $PATH_LAB_AD_CONTROLLER => {
            overlay use --prefix ./lab/ad/controller 
            controller build $state $img $debug
        },
        $PATH_LAB_AD_MEMBER => {
            overlay use --prefix ./lab/ad/member 
            member build $state $img $debug
        },
        _ => {
            error make $"unimplemented: match module: ($namepath)"
        },
    }
}

export def 'main build unattend' [
    namepath: path@namepaths,
    --nick: string, -n: string
    --inet: string = 'test', -i: string = 'test'
    --skip, -s
    --debug,
]: nothing -> path {
    if $nick != null and $in != null { err_exclusive_nick }
    
    let build = get_build $namepath
    let state = init $skip
    let img = make_img $build $state $in $inet $nick
    
    let iso_file = match $namepath {
        $PATH_LAB_WINDOWSERVER => {
            overlay use --prefix ./lab/windowserver 
            windowserver build_unattend $state $img $debug
        },
        $PATH_LAB_AD_CONTROLLER => {
            overlay use --prefix ./lab/ad/controller 
            controller build_unattend $state $img $debug
        },
        $PATH_LAB_AD_MEMBER => {
            overlay use --prefix ./lab/ad/member 
            member build_unattend $state $img $debug
        },
        _ => {
            error make $"unimplemented: match module: ($namepath)"
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

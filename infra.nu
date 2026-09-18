#!/usr/bin/env nu

const INFRA_DIR: directory = path self .
const CONFIG_DIRNAME: directory = 'sourcetrait/infra'
const INETS: list<string> = [default test infra]

const BUILDS: table<kind: string, namepath: path, hostname: string, subnet: list<string>> = [
    [ kind  namepath             hostname        subnet   ];
    [ vm    'lab/windowserver'   'windowserver'  [lab]    ]
    [ vm    'lab/ad/controller'  'controller'    [ad lab] ]
    [ vm    'lab/ad/member'      'member'        [ad lab] ]
]
const PATH_LAB_WINDOWSERVER: directory = 'lab/windowserver'
const PATH_LAB_AD_CONTROLLER: directory = 'lab/ad/controller'
const PATH_LAB_AD_MEMBER: directory = 'lab/ad/member'

export def namepaths []: nothing -> list<path> {
    $BUILDS | get namepath 
}

def init [skip: bool = false] {
  let pwrusr_repo = $INFRA_DIR | path join 'extern/pwrusr'
  if not ($pwrusr_repo | path join 'VERSION' | path exists) {
      error make $"extern/pwrusr does not exist"
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
      pwrusr_repo: $pwrusr_repo
      vm: {
        iso_dir: '/mnt/storage/kvm/iso'
        disk_dir: '/mnt/storage/kvm/disk'
        unattend_dir: '/mnt/storage/kvm/unattend'
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
        let name = $nick | str kebab-case | default -e null
        if $name == null {
            error make --unspanned $"invalid nick: ($nick)"
        }

        $out.name = $name
        $out.hostname = $name
    } else if $img != null {
        $out = $out | merge $img
    }

    $out
}

export def 'main build' [
    namepath: path@namepaths,
    --nick(-n): string
    --inet(-i): string = 'test'
    --skip(-s)
    --dry
    --debug
]: oneof<nothing,record> -> nothing {
    if $nick != null and $in != null { err_exclusive_nick }
    
    let build = get_build $namepath
    let state = init $skip
    let img = make_img $build $state $in $inet $nick
    
    match $namepath {
        $PATH_LAB_WINDOWSERVER => {
            overlay use --prefix ./vm/lab/windowserver 
            windowserver build $state $img $dry $debug
        },
        $PATH_LAB_AD_CONTROLLER => {
            overlay use --prefix ./vm/lab/ad/controller 
            controller build $state $img $dry $debug
        },
        $PATH_LAB_AD_MEMBER => {
            overlay use --prefix ./vm/lab/ad/member 
            member build $state $img $dry $debug
        },
        _ => {
            error make $"unimplemented: match module: ($namepath)"
        },
    }
}

export def 'main build unattend' [
    namepath: path@namepaths,
    --nick(-n): string
    --inet(-i): string = 'test'
    --skip(-s)
    --dry
    --debug
]: nothing -> path {
    if $nick != null and $in != null { err_exclusive_nick }
    
    let build = get_build $namepath
    let state = init $skip
    let img = make_img $build $state $in $inet $nick
    
    let iso_file = match $namepath {
        $PATH_LAB_WINDOWSERVER => {
            overlay use --prefix ./vm/lab/windowserver 
            windowserver build_unattend $state $img $dry $debug
        },
        $PATH_LAB_AD_CONTROLLER => {
            overlay use --prefix ./vm/lab/ad/controller 
            controller build_unattend $state $img $dry $debug
        },
        $PATH_LAB_AD_MEMBER => {
            overlay use --prefix ./vm/lab/ad/member 
            member build_unattend $state $img $dry $debug
        },
        _ => {
            error make $"unimplemented: match module: ($namepath)"
        },
    }
    
    $iso_file
}

# Downloads the ISO if it isn't already in the ISO dir.
def setup_virtio_win_iso [state: record]: nothing -> nothing {
  const VIRTIO_WIN_ISO: path = 'virtio-win.iso'
  const VIRTIO_WIN_ISO_URI: string = 'https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso'
  
  let virtio_win_iso: path = $state.path.vm.iso_dir | path join $VIRTIO_WIN_ISO

  if ($virtio_win_iso | path exists) { return }

  let tmpdir = (mktemp -d .virtio-win-iso.XXXXXX)
  let tmpfile = ($tmpdir | path join $VIRTIO_WIN_ISO)
  try {
    http get $VIRTIO_WIN_ISO_URI | save ($tmpdir | path join $VIRTIO_WIN_ISO)
    mv $tmpfile $virtio_win_iso
  } finally {
    rm $tmpdir
  }
}

def setup_windowserver_iso [state: record]: nothing -> nothing {
    const WINDOWS_SERVER_2025_EVAL_ISO: path = 'windows_server_2025_eval.iso'
    const WINDOWS_SERVER_2025_EVAL_NOPROMPT_ISO: path = 'windows_server_2025_eval.noprompt.iso'
    const WINDOWS_SERVER_2025_NOPROMPT_ISO: path = 'windows_server_2025.noprompt.iso'
    const WINDOWS_SERVER_2025_DIR: directory = 'windows/server/2025'
    
    # manually linked to an pre-existing iso download
    let windowserver_eval_iso_link: path = $state.path.vm.iso_dir | path join $WINDOWS_SERVER_2025_DIR $WINDOWS_SERVER_2025_EVAL_ISO
    # created by this function
    let windowserver_eval_noprompt_iso: path = $state.path.vm.iso_dir | path join $WINDOWS_SERVER_2025_DIR $WINDOWS_SERVER_2025_EVAL_NOPROMPT_ISO
    # linked to above at the iso dir
    let windowserver_noprompt_iso_link: path = $state.path.vm.iso_dir | path join $WINDOWS_SERVER_2025_NOPROMPT_ISO
    
    if ($windowserver_eval_noprompt_iso | path exists) { return }
    
    let label = (blkid -s LABEL -o value $windowserver_eval_iso_link)
    let tmpdir = (mktemp -d 'infra-setup.XXXXXX')
    let srcdir = ($tmpdir | path join 'src')
    let dstdir = ($tmpdir | path join 'dst')
    cd $tmpdir
    mkdir $srcdir $dstdir
    sudo mount -t udf $windowserver_eval_iso_link $srcdir
    cp --recursive --all ($"($srcdir)/*" | into glob) $dstdir
    sudo umount $srcdir
    
    chmod -R u+w $dstdir
    cd ($dstdir | path join 'efi/microsoft/boot')
    mv 'efisys.bin' 'efisys.bin.old'
    mv 'efisys_noprompt.bin' 'efisys.bin'
    cd $tmpdir
    
    (genisoimage -o $windowserver_eval_noprompt_iso
        -udf -iso-level 3 -allow-limited-size
        -J -joliet-long -R -D -N -relaxed-filenames
        -V $"($label)"
        -b boot/etfsboot.com -no-emul-boot -boot-load-size 8 -boot-info-table
        -eltorito-alt-boot
        -e efi/microsoft/boot/efisys.bin -no-emul-boot
        $dstdir)

    if ($windowserver_noprompt_iso_link | path exists) {
        rm $windowserver_noprompt_iso_link
    }
  
    cd $state.path.vm.iso_dir
    ln -s ($WINDOWS_SERVER_2025_DIR | path join $WINDOWS_SERVER_2025_EVAL_NOPROMPT_ISO) $WINDOWS_SERVER_2025_NOPROMPT_ISO
    
    rm -rf $tmpdir
}

export def 'main setup windows server' []: nothing -> nothing {
    let state = init
    sudo -v
    setup_windowserver_iso $state
    setup_virtio_win_iso $state
}

export def 'main delete' [name: string]: nothing -> nothing {
    let state = init
    let vm = virsh list --all | from ssv | skip 1 | where Name == $name | first
    if $vm == null {
        return
    }
    
    if $vm.State != 'shut off' {
        virsh -q destroy $name | ignore -eo
    }
    
    let r = virsh -q domblklist $name | complete
    if $r.exit_code == 0 {
        let paths = $r.stdout | from ssv --noheaders | get column1
        let todos = [
            [pool dir vol];
            [disk $state.path.vm.disk_dir $"($name).qcow2"]
            [unattend $state.path.vm.unattend_dir $"($name).unattend.iso"]
        ]
    
        for todo in $todos {
            let path = ($todo.dir | path join $todo.vol)
            if ($path in $paths) {
                virsh -q vol-delete --pool $todo.pool $todo.vol | ignore -eo
            }
        }
    }
    
    virsh -q undefine --nvram $name | ignore -eo
}

# do stuff
export def main [] { help infra }

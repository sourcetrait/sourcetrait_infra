##
# We attempt to keep dot-files out of ~/ and place them somewhere in ~/.sys.
# 
# Anything outside of to the XDG or UENV spec: ~/.sys/of.
###

# setup default env path to point at the app/bin and at cargo's bin
$env.PATH = ($env.PATH | append [
    ($nu.home-dir | path join '.sys/local/bin')
    ($nu.home-dir | path join '.sys/of/cargo/bin')
    ($nu.home-dir | path join '.sys/of/nu/bin')
    ($nu.home-dir | path join '.sys/my/exe')
])

$env.UENV_USR_SPEC = "usrlay"

$env.XDG_CACHE_HOME = ($nu.home-dir | path join '.sys/cache')
$env.XDG_CONFIG_HOME = ($nu.home-dir | path join '.config')
$env.XDG_DATA_HOME = ($nu.home-dir | path join '.sys/data')
$env.XDG_STATE_HOME = ($nu.home-dir | path join '.sys/state')

$env.UENV_USR_CACHE = ($nu.home-dir | path join '.sys/cache')
$env.UENV_USR_CONFIG = ($nu.home-dir | path join '.config')
$env.UENV_USR_DATA = ($nu.home-dir | path join '.sys/data')
$env.UENV_USR_STATE = ($nu.home-dir | path join '.sys/state')
$env.UENV_USR_TEMPORARY = ($nu.home-dir | path join 'tmp')
$env.UENV_USR_EXECUTE = ($nu.home-dir | path join '.sys/local/bin')
$env.UENV_USR_LIBRARY = ($nu.home-dir | path join '.sys/local/lib')
$env.UENV_USR_CONFIGURATION = ($nu.home-dir | path join '.sys/local/etc')
$env.UENV_USR_ASSET   = ($nu.home-dir | path join '.sys/local/share')
$env.UENV_USR_PACKAGE = ($nu.home-dir | path join '.sys/local/opt')
$env.UENV_USR_VARIABLE = ($nu.home-dir | path join '.sys/local/var')

$env.config.show_banner = false

$env.config.history = {
    file_format: sqlite
    isolation: true
    sync_on_enter: true
    max_size: 100_000_000
}

$env.LANG = "en_US.UTF-8"

# enable full color support
$env.COLORTERM = "truecolor"

# defualt editor is helix
$env.EDITOR = "hx"

if $nu.os-info.family == 'unix' {
    umask rwxr-x--- | ignore 
}

alias raw = open --raw

source src/usrlay.nu

$env.PROMPT_COMMAND       = {|| $"(ansi blue)(whoami)(ansi grey)@(sys host | get hostname) (ansi green)(usrlay prompt dir)(ansi purple)(usrlay prompt branch)(ansi reset)" }
$env.PROMPT_INDICATOR     = {|| "> " }
$env.PROMPT_COMMAND_RIGHT = {|| "" }


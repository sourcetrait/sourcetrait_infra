##
# We attempt to keep dot-files out of ~/ and place them somewhere in ~/.sys.
# 
# Anything outside of to the XDG or UENV spec: ~/.sys/hut.
###

# setup default env path to point at the app/bin and at cargo's bin
$env.PATH = ($env.PATH | append [
    ($nu.home-dir | path join '.sys/local/bin')
    ($nu.home-dir | path join '.sys/hut/cargo/bin')
    ($nu.home-dir | path join '.sys/nu/bin')
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

export module usrlay {
    # Simply list files ordered by type first
    export def l []: nothing -> table { %ls | sort-by type name }  

    # git status
    export def "g s" []: nothing -> nothing { ^git status }
    # git pull --rebase
    export def "g d" []: nothing -> nothing { ^git pull --rebase }
    # git push
    export def "g u" []: nothing -> nothing { ^git push }

    # git pull --rebase && git push
    export def "g du" []: nothing -> nothing {
        ^git pull --rebase
        ^git push
    }

    # git add . && git commit -m'...' OR git commit ($EDITOR)
    export def "g ac" [...rest]: nothing -> nothing {
        let msg = ($rest | str join ' ')
        ^git add .
        if ($msg | is-empty) {
            ^git commit
        } else {
            ^git commit -m$'($msg)'
        }
    }

    export def --env wrk [alias?: string]: nothing -> nothing {
        let wrk: record<default: directory, dirs: table<aliases: list<string>, dir: directory>> = open ($nu.default-config-dir | path join 'nuon' 'usrlay' 'work.nuon')

        if ($alias | is-empty) {
            cd $wrk.default
            return
        }

        mut $alias = $alias
        if ($alias == "?") {
            $alias = $wrk.dirs.aliases
                | each {|i| $i.0 }
                | input list --fuzzy $"(ansi cyan)where?(ansi reset)"
        }
    
        let dir: directory = $wrk.dirs
            | where {|i| $alias in $i.aliases }
            | get dir
            | first

        if ($dir | is-not-empty) {
            cd $dir
            if ((gstat --no-tag | get state) != "no_state") {
                ^git status
            }
        } else {
            print -e $"(ansi red)huh?(ansi reset)"
        }
    }
}

export module usrlay_prompt {
    export def dir []: nothing -> string {
        let sep = (char path_sep)
        let home = $nu.home-dir
        let pwd = $env.PWD
        let home_n = ($home | str replace --all $sep '/')
        let pwd_n = ($pwd | str replace --all $sep '/')
        if $pwd == $home { return "~" }
        if $pwd == "/" { return "/" }
        if ($pwd_n | str starts-with $"($home_n)/") {
            let comps = ($pwd_n | str replace $"($home_n)/" "" | path split | where {|c| $c != "/" })
            if ($comps | length) <= 2 {
                $"~/($comps | str join '/')"
            } else {
                $"($comps | last 2 | str join '/')"
            }
        } else {
            let comps = ($pwd_n | path split | where {|c| $c != "/" })
            if ($comps | length) <= 2 {
                $"/($comps | str join '/')"
            } else {
                $"($comps | last 2 | str join '/')"
            }
        }
    }

    export def branch []: nothing -> string {
        match (^git branch --show-current | complete | get stdout | default '' | str trim) {
            '' => '',
            $s => $" \(($s)\)"
        }
    }
}

use usrlay *
use usrlay_prompt

$env.PROMPT_COMMAND       = {|| $"(ansi blue)(whoami)(ansi grey)@(sys host | get hostname) (ansi green)(usrlay_prompt dir)(ansi purple)(usrlay_prompt branch)(ansi reset)" }
$env.PROMPT_INDICATOR     = {|| "> " }
$env.PROMPT_COMMAND_RIGHT = {|| "" }


export def --env wrk [alias?: string]: nothing -> nothing {
    let wrk: record<default: directory, dirs: table<aliases: list<string>, dir: directory>> = open ($nu.default-config-dir | path join 'usrlay' 'nuon' 'work.nuon')

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


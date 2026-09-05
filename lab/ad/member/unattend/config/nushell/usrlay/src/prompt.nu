export def 'usrlay prompt dir' []: nothing -> string {
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

export def 'usrlay prompt branch' []: nothing -> string {
    match (^git branch --show-current | complete | get stdout | default '' | str trim) {
        '' => '',
        $s => $" \(($s)\)"
    }
}

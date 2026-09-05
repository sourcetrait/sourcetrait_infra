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

# g r -> lists
# g r setup [host] [branch] -> setup relay and side-branch
# g r from [side] -> pull/rebase from relay
# g r to [side] -> push/rebase to relay
# g r sync -> sync between all relays and push to origin

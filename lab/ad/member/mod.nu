use ../../base/windowserver

export def build [state: record, img: record] {
    windowserver build $state $img
}

export def debug_build [state: record, img: record] {
    windowserver debug_build $state $img
}

export def debug_unattend [state: record, img: record]: nothing -> string {
    windowserver debug_unattend $state $img 
}

export def build_unattend [state: record, img: record]: nothing -> path {
    windowserver build_unattend $state $img
}

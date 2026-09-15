use ../../base/windowserver

export def build [state: record, img: record, debug: bool = false]: nothing -> nothing {
    windowserver build $state $img $debug
}

export def build_unattend [state: record, img: record, debug: bool = false]: nothing -> path {
    windowserver build_unattend $state $img
}

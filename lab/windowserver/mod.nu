use ../base/windowserver

export def build [state: record, img: record, dry: bool = false, debug: bool = false]: nothing -> nothing {
    windowserver build $state $img $dry $debug
}

export def build_unattend [state: record, img: record, dry: bool = false, debug: bool = false]: nothing -> path {
    windowserver build_unattend $state $img $dry $debug
}

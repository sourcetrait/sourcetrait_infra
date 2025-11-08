#!/bin/bash
set -eou pipefail
umask 067

function usage {
    local fmt=""
    local end_fmt=""

    if [[ "${1:-}" == "err" ]]; then
        fmt=""
        end_fmt=""
    fi

    echo "${fmt}usage:${end_fmt} $SCRIPT_USAGE"
    exit 1
}

function err {
    echo "error: ${1:-"unspecified error"}"
    exit 1
}

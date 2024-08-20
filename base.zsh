#!/bin/zsh

dbg() {
    [[ $VERBOSE == true ]] && echo "\e[47m\e[30m${1}\e[0m${2}" >&2
}

err() {
    echo "\e[41m${1}\e[0m$2" >&2
}

info() {
    printf "\e[32m${1}\e[0m${2}"
}

direct() {
    echo "\e[1m\e[34m$1\e[0m$2"
}
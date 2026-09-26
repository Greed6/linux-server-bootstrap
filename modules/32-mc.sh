#!/usr/bin/env bash
# @group   software
# @title   Midnight Commander (mc) | Midnight Commander (mc)
# @default on
# @os      all

module_run() {
    if command -v mc >/dev/null; then
        ok "mc $(L 'уже установлен' 'is already installed')"
        return 0
    fi
    pkg_install mc || return 1
    summary "mc $(L 'установлен' 'installed')"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

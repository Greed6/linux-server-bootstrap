#!/usr/bin/env bash
# @group   software
# @title   Редактор nano | nano editor
# @default on
# @os      all

module_run() {
    if command -v nano >/dev/null; then
        ok "nano $(L 'уже установлен' 'is already installed')"
        return 0
    fi
    pkg_install nano || return 1
    summary "nano $(L 'установлен' 'installed')"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

#!/usr/bin/env bash
# @group   repos
# @title   Обновить установленные пакеты | Upgrade installed packages
# @default on
# @os      all

module_run() {
    if [[ $FAMILY == debian ]]; then
        apt-get update -q </dev/null || return 1
        DEBIAN_FRONTEND=noninteractive apt-get -y -q \
            -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold dist-upgrade </dev/null || return 1
        apt-get -y -q autoremove </dev/null
    else
        $PKG -y upgrade </dev/null || return 1
    fi
    summary "$(L 'Пакеты обновлены' 'Packages upgraded')"
    if [[ -f /var/run/reboot-required ]] || { command -v needs-restarting >/dev/null && ! needs-restarting -r >/dev/null 2>&1; }; then
        warn "$(L 'Требуется перезагрузка (обновилось ядро или системные библиотеки)' 'Reboot required (kernel or system libraries updated)')"
    fi
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

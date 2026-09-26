#!/usr/bin/env bash
# @group   software
# @title   Базовые утилиты (curl, htop, git, tmux…) | Base tools (curl, htop, git, tmux…)
# @default on
# @os      all

module_run() {
    local dns def list p ok_list=() fail_list=()
    if [[ $FAMILY == debian ]]; then dns=dnsutils; else dns=bind-utils; fi
    def="curl wget htop git rsync tmux bash-completion unzip lsof tree jq ${dns}"
    ask list BASE_PACKAGES "$(L 'Пакеты через пробел' 'Packages, space separated')" "$def"

    # Ставим по одному: отсутствие одного пакета не мешает остальным
    for p in $list; do
        if pkg_installed "$p"; then
            ok_list+=("$p")
        elif pkg_install "$p" >/dev/null 2>&1; then
            ok_list+=("$p")
        else
            fail_list+=("$p")
        fi
    done
    ((${#ok_list[@]})) && summary "$(L 'Утилиты' 'Tools'): ${ok_list[*]}"
    ((${#fail_list[@]})) && warn "$(L 'Не установлены (нет в репозиториях?)' 'Not installed (missing in repositories?)'): ${fail_list[*]}"
    return 0
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

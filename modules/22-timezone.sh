#!/usr/bin/env bash
# @group   system
# @title   Часовой пояс | Timezone
# @default on
# @os      all

module_run() {
    local current tz c z i=1
    current=$(timedatectl show -p Timezone --value 2>/dev/null \
              || readlink -f /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
    info "$(L 'Текущий часовой пояс' 'Current timezone'): ${current:-unknown}"

    if ! tz=$(answer_get TIMEZONE); then
        local zones=(
            "Europe/Moscow|UTC+3 (Москва / Moscow)"
            "Europe/Kaliningrad|UTC+2"
            "Europe/Samara|UTC+4"
            "Asia/Yekaterinburg|UTC+5"
            "Asia/Omsk|UTC+6"
            "Asia/Novosibirsk|UTC+7"
            "Asia/Krasnoyarsk|UTC+7"
            "Asia/Irkutsk|UTC+8"
            "Asia/Yakutsk|UTC+9"
            "Asia/Vladivostok|UTC+10"
            "Asia/Magadan|UTC+11"
            "Asia/Kamchatka|UTC+12"
            "UTC|UTC+0"
        )
        for z in "${zones[@]}"; do
            printf '  %2d) %-20s %s\n' "$i" "${z%%|*}" "${z#*|}"
            i=$((i + 1))
        done
        printf '  %2d) %s\n' "$i" "$(L 'Ввести вручную (например Europe/Berlin)' 'Enter manually (e.g. Europe/Berlin)')"

        ask c TIMEZONE_CHOICE "$(L 'Выберите номер' 'Choose number')" 1
        if [[ $c =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#zones[@]} )); then
            tz=${zones[c-1]%%|*}
        elif [[ $c == "$i" ]]; then
            ask tz TIMEZONE_MANUAL "$(L 'Часовой пояс' 'Timezone')" "Europe/Moscow"
        else
            tz="Europe/Moscow"
        fi
    fi

    if [[ ! -f /usr/share/zoneinfo/$tz ]]; then
        pkg_ensure tzdata >/dev/null 2>&1
        [[ -f /usr/share/zoneinfo/$tz ]] || { err "$(L "Пояс $tz не найден" "Timezone $tz not found")"; return 1; }
    fi
    if has_systemd && timedatectl set-timezone "$tz" 2>/dev/null; then
        :
    else
        ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
        [[ $FAMILY == debian ]] && echo "$tz" > /etc/timezone
    fi
    summary "$(L 'Часовой пояс' 'Timezone'): $tz ($(date +%Z%z))"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

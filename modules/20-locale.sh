#!/usr/bin/env bash
# @group   system
# @title   Локализация (язык системы) | Localization (system language)
# @default off
# @os      all

module_run() {
    local c want
    echo "  1) ru_RU.UTF-8"
    echo "  2) en_US.UTF-8"
    ask c LOCALE_CHOICE "$(L 'Системная локаль' 'System locale')" "$( [[ $UI_LANG == ru ]] && echo 1 || echo 2 )"
    case $c in
        2|en*) want=en_US.UTF-8 ;;
        *)     want=ru_RU.UTF-8 ;;
    esac
    # Английскую держим всегда — на неё рассчитаны многие скрипты и логи
    locale_ensure en_US.UTF-8 || warn "en_US.UTF-8 $(L 'не добавлена' 'not added')"
    locale_ensure "$want" || { err "$(L "Не удалось добавить $want" "Failed to add $want")"; return 1; }
    locale_set_default "$want"

    if ask_yn LOCALE_UI "$(L 'Использовать этот язык и в меню linux-start?' 'Use this language in the linux-start menu too?')" y; then
        echo "${want:0:2}" > "$LS_STATE_DIR/lang"
    fi
    summary "$(L 'Системная локаль' 'System locale'): $want"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

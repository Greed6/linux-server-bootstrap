#!/usr/bin/env bash
#
# lib/menu.sh — реестр модулей и меню выбора / module registry and selection menu
#
# Модуль — файл modules/NN-<id>.sh. Метаданные читаются из комментариев:
#   # @group     system                      — id группы из lib/groups.conf
#   # @title     Часовой пояс | Timezone     — название RU | EN
#   # @default   on|off                      — отмечен ли в меню по умолчанию
#   # @os        all | debian | rhel | astra,redos | !astra   — где доступен
#   # @conflicts fail2ban                    — с какими модулями не сочетается
# NN задаёт порядок выполнения. / NN defines the execution order.

GROUP_IDS=()
declare -A GROUP_TITLE=()
MOD_IDS=()
declare -A MOD_FILE=() MOD_GROUP=() MOD_TITLE=() MOD_DEFAULT=() MOD_CONFLICTS=()
declare -A SEL=()

_trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

_meta() { sed -nE "s/^#[[:space:]]*@$2[[:space:]]+//p" "$1" | head -n1; }

# os_matches "debian,!astra" — подходит ли модуль к текущей ОС
os_matches() {
    local spec=${1//,/ } tok positive=0 matched=0
    [[ -z $spec || $spec == all ]] && return 0
    for tok in $spec; do
        if [[ $tok == !* ]]; then
            [[ ${tok#!} == "$OS_ID" || ${tok#!} == "$FAMILY" ]] && return 1
        else
            positive=1
            [[ $tok == "$OS_ID" || $tok == "$FAMILY" ]] && matched=1
        fi
    done
    (( positive == 0 || matched == 1 ))
}

load_groups() {
    local id ru en
    while IFS='|' read -r id ru en; do
        id=$(_trim "$id")
        [[ -z $id || $id == \#* ]] && continue
        GROUP_IDS+=("$id")
        GROUP_TITLE[$id]=$(_trim "$(L "$ru" "$en")")
    done < "$LS_ROOT/lib/groups.conf"
}

load_modules() {
    local f id title group
    load_groups
    for f in "$LS_ROOT"/modules/[0-9]*.sh; do
        [[ -f $f ]] || continue
        id=$(basename "$f" .sh); id=${id#*-}
        os_matches "$(_meta "$f" os)" || continue
        title=$(_meta "$f" title)
        group=$(_meta "$f" group)
        [[ -n ${GROUP_TITLE[$group]:-} ]] || group=other
        MOD_IDS+=("$id")
        MOD_FILE[$id]=$f
        MOD_GROUP[$id]=$group
        MOD_TITLE[$id]=$(_trim "$(L "${title%%|*}" "${title#*|}")")
        MOD_DEFAULT[$id]=$(_meta "$f" default)
        MOD_CONFLICTS[$id]=$(_meta "$f" conflicts)
    done
}

# Модули в порядке отображения (по группам)
modules_in_group() {
    local id
    for id in "${MOD_IDS[@]}"; do
        [[ ${MOD_GROUP[$id]} == "$1" ]] && echo "$id"
    done
}

# Отметки по умолчанию: при первой настройке — модули с @default on.
# При повторном запуске (что-то уже выполнялось) меню открывается пустым:
# отмечаете только то, что нужно доустановить.
init_selection() {
    local id rerun=0
    [[ -s $LS_STATE_DIR/done ]] && rerun=1
    for id in "${MOD_IDS[@]}"; do
        if (( ! rerun )) && [[ ${MOD_DEFAULT[$id]} == on ]]; then SEL[$id]=1; else SEL[$id]=0; fi
    done
}

# select_ids "id1 id2" — выбор списком (из --modules / LS_MODULES)
select_ids() {
    local id
    for id in "${MOD_IDS[@]}"; do SEL[$id]=0; done
    for id in ${1//,/ }; do
        if [[ -n ${MOD_FILE[$id]:-} ]]; then
            SEL[$id]=1
        else
            warn "$(L 'Неизвестный или неподходящий для этой ОС модуль' 'Unknown module or not applicable to this OS'): $id"
        fi
    done
}

selected_ids() {
    local id
    for id in "${MOD_IDS[@]}"; do [[ ${SEL[$id]} == 1 ]] && echo "$id"; done
}

_done_mark() { is_done "$1" && printf ' ✓'; }

menu_whiptail() {
    local args=() g id rows cols h w lh out
    for g in "${GROUP_IDS[@]}"; do
        [[ -z $(modules_in_group "$g") ]] && continue
        args+=("#$g" "=== ${GROUP_TITLE[$g]} ===" OFF)
        for id in $(modules_in_group "$g"); do
            args+=("$id" "    ${MOD_TITLE[$id]}$(_done_mark "$id")" "$([[ ${SEL[$id]} == 1 ]] && echo ON || echo OFF)")
        done
    done
    rows=$(tput lines </dev/tty 2>/dev/null || echo 24)
    cols=$(tput cols </dev/tty 2>/dev/null || echo 80)
    h=$(( rows - 2 )); (( h > 40 )) && h=40
    w=$(( cols - 4 )); (( w > 76 )) && w=76
    lh=$(( h - 8 ))

    out=$(whiptail --title "linux-start" --notags --separate-output \
        --ok-button "$(L 'Установить' 'Install')" --cancel-button "$(L 'Выход' 'Exit')" \
        --checklist "$(L 'Пробел — отметить, Tab — к кнопкам, Enter — установить.  ✓ — уже выполнялось' \
                         'Space — toggle, Tab — buttons, Enter — install.  ✓ — already done')" \
        "$h" "$w" "$lh" "${args[@]}" 2>&1 >/dev/tty </dev/tty) || return 1

    for id in "${MOD_IDS[@]}"; do SEL[$id]=0; done
    while IFS= read -r id; do
        [[ -z $id || $id == \#* ]] && continue
        SEL[$id]=1
    done <<< "$out"
}

menu_text() {
    local g id n input tok a b i
    local -a idx
    while true; do
        idx=()
        n=0
        {
            echo
            printf '%s linux-start — %s%s\n' "$C_BOLD" "$(L 'выберите, что настроить' 'choose what to set up')" "$C_RESET"
            for g in "${GROUP_IDS[@]}"; do
                [[ -z $(modules_in_group "$g") ]] && continue
                printf '\n  %s%s%s\n' "$C_BOLD" "${GROUP_TITLE[$g]}" "$C_RESET"
                for id in $(modules_in_group "$g"); do
                    n=$((n + 1)); idx[n]=$id
                    printf '   [%s] %2d) %s%s\n' "$([[ ${SEL[$id]} == 1 ]] && echo x || echo ' ')" \
                        "$n" "${MOD_TITLE[$id]}" "$(_done_mark "$id")"
                done
            done
            echo
            L '  Номера (1 3 5-7) — переключить, a — все, 0 — снять все,' \
              '  Numbers (1 3 5-7) — toggle, a — all, 0 — none,'
            echo
            L '  Enter — установить, q — выход' '  Enter — install, q — quit'
            printf '\n  > '
        } >/dev/tty
        read -r input </dev/tty || return 1
        case $input in
            "")   return 0 ;;
            q|Q)  return 1 ;;
            a|A)  for id in "${MOD_IDS[@]}"; do SEL[$id]=1; done ;;
            0)    for id in "${MOD_IDS[@]}"; do SEL[$id]=0; done ;;
            *)
                for tok in ${input//,/ }; do
                    if [[ $tok =~ ^([0-9]+)-([0-9]+)$ ]]; then
                        a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
                    elif [[ $tok =~ ^[0-9]+$ ]]; then
                        a=$tok; b=$tok
                    else
                        continue
                    fi
                    for ((i = a; i <= b; i++)); do
                        id=${idx[i]:-}
                        [[ -n $id ]] && SEL[$id]=$(( 1 - SEL[$id] ))
                    done
                done ;;
        esac
    done
}

# show_menu [text] — 0 = выбор сделан, 1 = выход
show_menu() {
    if [[ ${1:-} != text ]] && command -v whiptail >/dev/null && [[ ${TERM:-dumb} != dumb ]]; then
        menu_whiptail
    else
        menu_text
    fi
}

# Предупреждение о конфликтующих модулях; 1 = вернуться в меню
check_conflicts() {
    local id c
    for id in $(selected_ids); do
        for c in ${MOD_CONFLICTS[$id]//,/ }; do
            [[ ${SEL[$c]:-0} == 1 ]] || continue
            warn "$(L "«${MOD_TITLE[$id]}» и «${MOD_TITLE[$c]}» обычно не используют вместе" \
                      "\"${MOD_TITLE[$id]}\" and \"${MOD_TITLE[$c]}\" are usually not used together")"
            ask_yn CONFLICTS_OK "$(L 'Продолжить с обоими?' 'Continue with both?')" n || return 1
            return 0
        done
    done
    return 0
}

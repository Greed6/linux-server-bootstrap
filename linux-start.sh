#!/usr/bin/env bash
#
# linux-start.sh — первичная настройка Linux-сервера / initial Linux server setup
#
# Поддержка / Supported:
#   Ubuntu 22.04/24.04, Debian 12/13, RHEL / Rocky / AlmaLinux / Oracle Linux 8/9,
#   CentOS 7 / 8 / Stream 8 / 9 / 10
#
# Повторный запуск / Re-run:  sudo linux-start
#
# Каждая задача — отдельный модуль в modules/, меню строится автоматически.
# Every task is a separate module in modules/, the menu is built automatically.

set -uo pipefail

LS_VERSION="2.1.0"
LS_ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
export LS_ROOT LS_VERSION

usage() {
    cat <<'EOF'
Usage: sudo ./linux-start.sh [options]

  -c, --config FILE     файл ответов / answers file (see answers.example.conf)
  -y, --yes             без вопросов: ответы из файла или по умолчанию
                        non-interactive: answers from file or defaults
  -l, --lang ru|en      язык интерфейса / interface language
  -m, --modules "a b"   выполнить модули без меню / run modules without menu
      --list            список модулей / list modules
      --text-menu       текстовое меню вместо whiptail / text menu instead of whiptail
  -h, --help
EOF
}

ARG_CONFIG="" ARG_LANG="" ARG_MODULES="" ARG_TEXT_MENU=0 ARG_LIST=0
while (($#)); do
    case $1 in
        -c|--config)   ARG_CONFIG=${2:-}; shift ;;
        -y|--yes)      export LS_NONINTERACTIVE=1 ;;
        -l|--lang)     ARG_LANG=${2:-}; shift ;;
        -m|--modules)  ARG_MODULES=${2:-}; shift ;;
        --list)        ARG_LIST=1 ;;
        --text-menu)   ARG_TEXT_MENU=1 ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

if [[ -n $ARG_CONFIG ]]; then
    [[ -r $ARG_CONFIG ]] || { echo "Cannot read config: $ARG_CONFIG" >&2; exit 1; }
    set -a
    # shellcheck disable=SC1090
    . "$ARG_CONFIG"
    set +a
fi
[[ -n $ARG_LANG ]] && export UI_LANG=$ARG_LANG
[[ -z ${UI_LANG:-} && -n ${LS_LANG:-} ]] && export UI_LANG=$LS_LANG

# shellcheck source=lib/common.sh
. "$LS_ROOT/lib/common.sh"
# shellcheck source=lib/menu.sh
. "$LS_ROOT/lib/menu.sh"

# Первый запуск: русская локаль по умолчанию? От ответа зависит язык меню.
first_run_language() {
    if [[ -n $ARG_LANG || -n ${LS_LANG:-} ]]; then
        [[ $UI_LANG == ru ]] && locale_ensure ru_RU.UTF-8
    elif [[ -f $LS_STATE_DIR/lang ]]; then
        UI_LANG=$(cat "$LS_STATE_DIR/lang")
    else
        UI_LANG=en
        if ask_yn RU_LOCALE "Установить русскую локализацию по умолчанию? / Install Russian locale as default?" y; then
            UI_LANG=ru
            if locale_ensure ru_RU.UTF-8; then
                locale_set_default ru_RU.UTF-8
                summary "Системная локаль: ru_RU.UTF-8"
            else
                warn "Не удалось добавить ru_RU.UTF-8 / Failed to add ru_RU.UTF-8"
            fi
        else
            locale_ensure en_US.UTF-8 || warn "Failed to add en_US.UTF-8"
        fi
    fi
    [[ $UI_LANG == ru ]] && has_locale ru_RU.UTF-8 && export LANG=ru_RU.UTF-8
    [[ $UI_LANG == en ]] && has_locale en_US.UTF-8 && export LANG=en_US.UTF-8
    export UI_LANG
    echo "$UI_LANG" > "$LS_STATE_DIR/lang"
}

list_modules() {
    local g id
    for g in "${GROUP_IDS[@]}"; do
        [[ -z $(modules_in_group "$g") ]] && continue
        echo "${GROUP_TITLE[$g]}:"
        for id in $(modules_in_group "$g"); do
            printf '  %-20s %-3s %s%s\n' "$id" "${MOD_DEFAULT[$id]}" "${MOD_TITLE[$id]}" "$(_done_mark "$id")"
        done
    done
}

run_modules() {
    local id rc results=() failed=0
    for id in $(selected_ids); do
        step "${MOD_TITLE[$id]}"
        # Каждый модуль — в своей подоболочке: ошибка одного не ломает остальные
        # shellcheck disable=SC1090
        ( . "${MOD_FILE[$id]}"; module_run )
        rc=$?
        if (( rc == 0 )); then
            mark_done "$id"
            results+=("${C_GREEN}✓${C_RESET} ${MOD_TITLE[$id]}")
        else
            failed=$((failed + 1))
            results+=("${C_RED}✗${C_RESET} ${MOD_TITLE[$id]} (rc=$rc)")
        fi
    done

    step "$(L 'Итог' 'Summary')"
    printf '  %s\n' "${results[@]}"
    if [[ -s $LS_SUMMARY_FILE ]]; then
        echo
        sed 's/^/  • /' "$LS_SUMMARY_FILE"
    fi
    echo
    info "$(L 'Журнал' 'Log'): $LS_LOG_FILE"
    [[ -d $LS_BACKUP_DIR ]] && info "$(L 'Бэкапы изменённых файлов' 'Backups of changed files'): $LS_BACKUP_DIR"
    return $(( failed > 0 ))
}

# Команда linux-start для повторного запуска / re-run command
install_launcher() {
    local root=$LS_ROOT link=/usr/local/sbin/linux-start dest=/opt/linux-server-bootstrap
    # Из временного каталога копируем в /opt, иначе ссылка пропадёт после перезагрузки
    case $root in
        /tmp/*|/var/tmp/*|/dev/shm/*)
            mkdir -p "$dest" && cp -a "$root/." "$dest/" && root=$dest
            info "$(L "Скрипт скопирован в $dest" "Script copied to $dest")" ;;
    esac
    [[ $(readlink -f "$link" 2>/dev/null) == "$root/linux-start.sh" ]] && return 0
    mkdir -p "$(dirname "$link")"
    ln -sfn "$root/linux-start.sh" "$link" \
        && info "$(L 'Повторный запуск в любой момент: sudo linux-start' 'Re-run at any time: sudo linux-start')"
}

# Меню → подтверждение → выполнение. 0 = выполнено, 1 = выход без изменений
select_and_run() {
    local want=$1 sel id
    if [[ -n $want ]]; then
        select_ids "$want"
    else
        init_selection
        if [[ $LS_NONINTERACTIVE != 1 ]]; then
            while true; do
                show_menu "$( ((ARG_TEXT_MENU)) && echo text)" || return 1
                check_conflicts && break
            done
        fi
    fi

    sel=$(selected_ids)
    [[ -z $sel ]] && { info "$(L 'Ничего не выбрано' 'Nothing selected')"; return 1; }
    echo
    info "$(L 'Будет выполнено' 'Will run'):"
    for id in $sel; do echo "    - ${MOD_TITLE[$id]}"; done
    ask_yn CONFIRM "$(L 'Начать?' 'Start?')" y || return 1

    : > "$LS_SUMMARY_FILE"
    run_modules
    LAST_RC=$?
    return 0
}

main() {
    if (( ARG_LIST )); then
        load_modules; list_modules; exit 0
    fi
    [[ $EUID -eq 0 ]] || die "Запустите от root / Run as root: sudo $0"

    mkdir -p "$LS_STATE_DIR" "$(dirname "$LS_LOG_FILE")"
    exec > >(tee -a "$LS_LOG_FILE") 2>&1
    echo "===== linux-start $LS_VERSION  $(date '+%F %T') ====="

    LS_SUMMARY_FILE=$(mktemp)
    export LS_SUMMARY_FILE
    trap 'rm -f "$LS_SUMMARY_FILE"' EXIT
    trap 'echo; err "Прервано / Interrupted"; exit 130' INT

    first_run_language
    load_modules
    info "$(L 'Система' 'System'): $OS_NAME ($FAMILY, $PKG)"

    install_launcher

    local want=${ARG_MODULES:-${LS_MODULES:-}}
    # Интерактивно после установки можно вернуться в меню и доустановить компоненты
    while true; do
        if ! select_and_run "$want"; then
            info "$(L 'Выход без изменений' 'Exit without changes')"
            break
        fi
        [[ -n $want || $LS_NONINTERACTIVE == 1 ]] && break
        echo
        ask_yn MENU_AGAIN "$(L 'Вернуться в меню, чтобы доустановить компоненты?' \
                               'Back to the menu to install more components?')" n || break
    done
    info "$(L 'Повторный запуск: sudo linux-start' 'Re-run: sudo linux-start')"
    return "${LAST_RC:-0}"
}

main "$@"

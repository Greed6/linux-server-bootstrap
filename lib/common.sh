#!/usr/bin/env bash
#
# lib/common.sh — общие функции linux-start / shared helpers
#
# Подключается главным скриптом и каждым модулем.
# Sourced by the main script and by every module.

[[ -n ${LS_COMMON_LOADED:-} ]] && return 0
LS_COMMON_LOADED=1

# bash < 4.4 (CentOS 7) считает пустой массив "${arr[@]}" неопределённой
# переменной при set -u — там nounset отключаем.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
    set +u
fi

LS_ROOT=${LS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
LS_STATE_DIR=${LS_STATE_DIR:-/var/lib/linux-start}
LS_LOG_FILE=${LS_LOG_FILE:-/var/log/linux-start.log}
LS_BACKUP_DIR=${LS_BACKUP_DIR:-/var/backups/linux-start/$(date +%Y%m%d-%H%M%S)}
LS_SUMMARY_FILE=${LS_SUMMARY_FILE:-/dev/null}
LS_NONINTERACTIVE=${LS_NONINTERACTIVE:-0}
export LS_ROOT LS_STATE_DIR LS_LOG_FILE LS_BACKUP_DIR LS_SUMMARY_FILE LS_NONINTERACTIVE

# Цвета определяем до перенаправления вывода в tee
if [[ -z ${LS_COLOR:-} ]]; then
    if [[ -t 1 ]]; then LS_COLOR=1; else LS_COLOR=0; fi
fi
export LS_COLOR
if [[ $LS_COLOR == 1 ]]; then
    C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'
    C_BOLD=$'\e[1m'; C_RESET=$'\e[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi

if [[ -z ${UI_LANG:-} ]]; then
    UI_LANG=$(cat "$LS_STATE_DIR/lang" 2>/dev/null || echo en)
fi
export UI_LANG

# --------------------------------------------------------------------------
# Вывод / Output
# --------------------------------------------------------------------------

# L "русский текст" "english text"
L() { if [[ $UI_LANG == ru ]]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

info() { printf '%s[*]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
step() { printf '\n%s==== %s ====%s\n' "$C_BOLD" "$*" "$C_RESET"; }

# summary "текст" — строка в итоговый отчёт
summary() { printf '%s\n' "$*" >> "$LS_SUMMARY_FILE"; ok "$*"; }

# --------------------------------------------------------------------------
# Ввод / Input
#
# У каждого вопроса есть ключ. Если в файле ответов (--config) задана
# переменная LS_<КЛЮЧ>, вопрос не задаётся. В режиме --yes без ответа
# берётся значение по умолчанию.
#
# Every question has a key. If LS_<KEY> is set in the answers file (--config),
# the question is skipped. In --yes mode the default is used.
# --------------------------------------------------------------------------

has_tty() {
    [[ $LS_NONINTERACTIVE != 1 ]] && { : </dev/tty; } 2>/dev/null
}

# answer_get KEY — печатает LS_KEY, если переменная задана
answer_get() {
    local v="LS_$1"
    declare -p "$v" >/dev/null 2>&1 || return 1
    printf '%s' "${!v}"
}

_is_secret_key() { [[ $1 == *TOKEN* || $1 == *PASSWORD* || $1 == *ENROLL_KEY* ]]; }

# ask VAR KEY "вопрос" "по умолчанию"
ask() {
    local __var=$1 key=$2 q=$3 def=${4:-} ans shown
    if ans=$(answer_get "$key"); then
        shown=$ans; _is_secret_key "$key" && shown="***"
        info "$q: $shown"
    elif has_tty; then
        if [[ -n $def ]]; then
            printf '%s?%s %s [%s]: ' "$C_YELLOW" "$C_RESET" "$q" "$def" >/dev/tty
        else
            printf '%s?%s %s: ' "$C_YELLOW" "$C_RESET" "$q" >/dev/tty
        fi
        read -r ans </dev/tty || ans=""
        ans=${ans:-$def}
        shown=$ans; _is_secret_key "$key" && shown="***"
        echo "[answer] $q: $shown" >> "$LS_LOG_FILE" 2>/dev/null
    else
        ans=$def
        info "$q: $def ($(L 'по умолчанию' 'default'))"
    fi
    printf -v "$__var" '%s' "$ans"
}

# ask_secret VAR KEY "вопрос" — ввод без эха
ask_secret() {
    local __var=$1 key=$2 q=$3 ans=""
    if ans=$(answer_get "$key"); then
        info "$q: ***"
    elif has_tty; then
        printf '%s?%s %s: ' "$C_YELLOW" "$C_RESET" "$q" >/dev/tty
        read -rs ans </dev/tty || ans=""
        echo >/dev/tty
    fi
    printf -v "$__var" '%s' "$ans"
}

_yn_value() {
    case $1 in
        y|Y|yes|Yes|YES|1|true|on|д|Д|да|Да|ДА)   return 0 ;;
        n|N|no|No|NO|0|false|off|н|Н|нет|Нет|НЕТ) return 1 ;;
    esac
    return 2
}

# ask_yn KEY "вопрос" y|n — 0 = да, 1 = нет
ask_yn() {
    local key=$1 q=$2 def=${3:-y} ans hint rc
    if ans=$(answer_get "$key"); then
        _yn_value "$ans"; rc=$?
        if (( rc == 2 )); then _yn_value "$def"; rc=$?; fi
        info "$q: $( ((rc == 0)) && L 'да' 'yes' || L 'нет' 'no')"
        return $rc
    fi
    if ! has_tty; then
        _yn_value "$def"; rc=$?
        info "$q: $( ((rc == 0)) && L 'да' 'yes' || L 'нет' 'no') ($(L 'по умолчанию' 'default'))"
        return $rc
    fi
    [[ $def == y ]] && hint="[Y/n]" || hint="[y/N]"
    while true; do
        printf '%s?%s %s %s: ' "$C_YELLOW" "$C_RESET" "$q" "$hint" >/dev/tty
        read -r ans </dev/tty || ans=""
        _yn_value "${ans:-$def}"; rc=$?
        if (( rc != 2 )); then
            echo "[answer] $q: $( ((rc == 0)) && echo yes || echo no)" >> "$LS_LOG_FILE" 2>/dev/null
            return $rc
        fi
    done
}

# --------------------------------------------------------------------------
# Бэкапы и состояние / Backups and state
# --------------------------------------------------------------------------

backup() {
    local f
    for f in "$@"; do
        [[ -e $f ]] || continue
        [[ -e $LS_BACKUP_DIR$f ]] && continue   # храним самую первую версию за запуск
        mkdir -p "$LS_BACKUP_DIR$(dirname "$f")"
        cp -a "$f" "$LS_BACKUP_DIR$f"
    done
}

restore() {
    local f
    for f in "$@"; do
        [[ -e $LS_BACKUP_DIR$f ]] && cp -a "$LS_BACKUP_DIR$f" "$f"
    done
    return 0
}

mark_done() {
    mkdir -p "$LS_STATE_DIR"
    sed -i "/^$1 /d" "$LS_STATE_DIR/done" 2>/dev/null
    echo "$1 $(date '+%F %T')" >> "$LS_STATE_DIR/done"
}

is_done() { grep -q "^$1 " "$LS_STATE_DIR/done" 2>/dev/null; }

# --------------------------------------------------------------------------
# ОС и пакеты / OS and packages
# --------------------------------------------------------------------------

detect_os() {
    [[ -r /etc/os-release ]] || die "/etc/os-release not found"
    local ID="" PRETTY_NAME="" VERSION_ID="" VERSION_CODENAME=""
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID=${ID,,}
    OS_NAME=${PRETTY_NAME:-$OS_ID}
    OS_VER=${VERSION_ID:-}
    OS_MAJOR=${OS_VER%%.*}
    OS_CODENAME=${VERSION_CODENAME:-}

    case $OS_ID in
        ubuntu|debian)                  FAMILY=debian ;;
        rhel|centos|rocky|almalinux|ol) FAMILY=rhel ;;
        *) die "Unsupported OS: $OS_NAME. Supported: Ubuntu, Debian, RHEL, CentOS, Rocky, AlmaLinux, Oracle Linux" ;;
    esac

    if [[ $FAMILY == rhel ]]; then
        if command -v dnf >/dev/null; then PKG=dnf; else PKG=yum; fi
        SSH_SVC=sshd
    else
        PKG=apt
        SSH_SVC=ssh
    fi
    export OS_ID OS_NAME OS_VER OS_MAJOR OS_CODENAME FAMILY PKG SSH_SVC
}

# stdin пакетного менеджера — /dev/null, чтобы он не «съедал» ввод пользователя
pkg_update() {
    if [[ $FAMILY == debian ]]; then apt-get update -q </dev/null; else $PKG makecache -q </dev/null; fi
}

pkg_install() {
    if [[ $FAMILY == debian ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
            -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@" </dev/null
    else
        $PKG install -y -q "$@" </dev/null
    fi
}

pkg_available() {
    if [[ $FAMILY == debian ]]; then
        apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: [^(]'
    else
        $PKG -q info "$1" >/dev/null 2>&1
    fi
}

pkg_installed() {
    if [[ $FAMILY == debian ]]; then
        dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
    else
        # --whatprovides: curl-minimal тоже считается как curl
        rpm -q --whatprovides "$1" >/dev/null 2>&1
    fi
}

# pkg_ensure pkg... — ставит то, чего нет; 0 если в итоге всё установлено
pkg_ensure() {
    local p missing=()
    for p in "$@"; do pkg_installed "$p" || missing+=("$p"); done
    ((${#missing[@]})) || return 0
    pkg_install "${missing[@]}"
}

# --------------------------------------------------------------------------
# systemd
# --------------------------------------------------------------------------

# systemd работает, если отвечает systemctl (каталога /run/systemd/system недостаточно)
has_systemd() {
    if [[ -z ${LS_HAS_SYSTEMD:-} ]]; then
        if command -v systemctl >/dev/null && [[ -d /run/systemd/system ]] \
            && systemctl list-units --no-pager >/dev/null 2>&1; then
            LS_HAS_SYSTEMD=1
        else
            LS_HAS_SYSTEMD=0
        fi
    fi
    [[ $LS_HAS_SYSTEMD == 1 ]]
}

svc_exists() { systemctl list-unit-files "$1.service" 2>/dev/null | grep -q "^$1\.service"; }
svc_active() { has_systemd && systemctl is-active --quiet "$1" 2>/dev/null; }

svc_enable_now() {
    if ! has_systemd; then
        warn "systemd $(L 'не запущен — служба' 'is not running — service') $1 $(L 'не запущена' 'not started')"
        return 1
    fi
    systemctl enable "$1" >/dev/null 2>&1
    systemctl restart "$1"
}

svc_disable_now() { has_systemd && systemctl disable --now "$1" >/dev/null 2>&1; return 0; }

# --------------------------------------------------------------------------
# Файрвол / Firewall
# --------------------------------------------------------------------------

detect_fw() {
    if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q 'Status: active'; then
        echo ufw
    elif svc_active firewalld; then
        echo firewalld
    fi
}

# fw_allow <port> [proto] [comment]
fw_allow() {
    local port=$1 proto=${2:-tcp} comment=${3:-} fw
    fw=$(detect_fw)
    case $fw in
        ufw)
            ufw allow "${port}/${proto}" comment "$comment" >/dev/null 2>&1 \
                || ufw allow "${port}/${proto}" >/dev/null
            ;;
        firewalld)
            firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null \
                && firewall-cmd --reload >/dev/null
            ;;
        *)
            info "$(L "Файрвол не активен — порт $port/$proto открывать не нужно" \
                      "No active firewall — no need to open $port/$proto")"
            return 0
            ;;
    esac
    summary "$(L 'Открыт порт' 'Port opened') $port/$proto${comment:+ ($comment)} [$fw]"
}

# --------------------------------------------------------------------------
# SSH
# --------------------------------------------------------------------------

sshd_bin() { command -v sshd 2>/dev/null || echo /usr/sbin/sshd; }

# "OpenSSH_8.9p1" → 89
ssh_version() {
    local v
    v=$(ssh -V 2>&1 | sed -nE 's/^OpenSSH_([0-9]+)\.([0-9]+).*/\1\2/p')
    echo "${v:-0}"
}

# Без host-ключей sshd -t/-T завершаются ошибкой (sshd ещё ни разу не запускался)
ensure_host_keys() {
    ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || ssh-keygen -A >/dev/null 2>&1
    return 0
}

# Порты, на которых слушает sshd (по итоговой конфигурации)
sshd_ports() {
    local ports
    ensure_host_keys
    mkdir -p /run/sshd 2>/dev/null
    ports=$("$(sshd_bin)" -T 2>/dev/null | awk '$1 == "port" {print $2}' | sort -un | tr '\n' ' ')
    [[ -z $ports ]] && ports="22"
    echo "${ports% }"
}

sshd_restart() {
    if ! has_systemd; then
        warn "systemd $(L 'не запущен — перезапустите sshd вручную' 'is not running — restart sshd manually')"
        return 0
    fi
    # Ubuntu 22.10+: sshd запускается через ssh.socket, порт берётся генератором
    if systemctl is-enabled --quiet ssh.socket 2>/dev/null || systemctl is-active --quiet ssh.socket 2>/dev/null; then
        systemctl daemon-reload
        systemctl restart ssh.socket
    fi
    systemctl restart "$SSH_SVC"
}

# sshd_write_block <имя> <содержимое>
#
# В sshd побеждает ПЕРВОЕ встреченное значение, поэтому наши настройки
# кладём в drop-in с префиксом 00 (OpenSSH ≥ 8.2) либо в начало sshd_config.
sshd_write_block() {
    local name=$1 content=$2 main=/etc/ssh/sshd_config ver tmp
    local dropin="/etc/ssh/sshd_config.d/00-linux-start-${name}.conf"
    ver=$(ssh_version)
    backup "$main" "$dropin"

    if (( ver >= 82 )); then
        mkdir -p /etc/ssh/sshd_config.d
        if ! grep -qiE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' "$main"; then
            sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$main"
        fi
        printf '# linux-start: %s\n%s\n' "$name" "$content" > "$dropin"
        chmod 600 "$dropin"
    else
        sed -i "/^# >>> linux-start $name/,/^# <<< linux-start $name/d" "$main"
        tmp=$(mktemp)
        {
            echo "# >>> linux-start $name"
            printf '%s\n' "$content"
            echo "# <<< linux-start $name"
            echo
            cat "$main"
        } > "$tmp" && cat "$tmp" > "$main"
        rm -f "$tmp"
    fi

    mkdir -p /run/sshd
    ensure_host_keys
    if "$(sshd_bin)" -t; then
        sshd_restart
        return 0
    fi
    err "$(L 'Ошибка в конфигурации sshd — откатываю' 'sshd config error — reverting')"
    rm -f "$dropin"
    restore "$main" "$dropin"
    return 1
}

sudo_group() {
    local g
    for g in sudo wheel; do
        getent group "$g" >/dev/null && { echo "$g"; return; }
    done
}

selinux_enabled() {
    command -v getenforce >/dev/null && [[ $(getenforce 2>/dev/null) != Disabled ]]
}

# --------------------------------------------------------------------------
# Локаль / Locale
# --------------------------------------------------------------------------

has_locale() { locale -a 2>/dev/null | grep -qiE "^${1%%.*}\.utf-?8$"; }

# locale_ensure ru_RU.UTF-8
locale_ensure() {
    local want=$1
    has_locale "$want" && return 0
    info "$(L "Добавляю локаль $want…" "Adding locale $want…")"
    if [[ $FAMILY == debian ]]; then
        if ! command -v locale-gen >/dev/null; then
            apt-get update -q </dev/null >/dev/null 2>&1
            pkg_install locales >/dev/null
        fi
        backup /etc/locale.gen
        touch /etc/locale.gen
        sed -i -E "s/^#\s*(${want//./\\.} UTF-8)/\1/" /etc/locale.gen
        grep -q "^${want} UTF-8" /etc/locale.gen || echo "${want} UTF-8" >> /etc/locale.gen
        locale-gen >/dev/null
    else
        pkg_install "glibc-langpack-${want%%_*}" >/dev/null 2>&1 \
            || localedef -i "${want%%.*}" -f UTF-8 "$want"
    fi
    has_locale "$want"
}

locale_set_default() {
    local want=$1
    if command -v localectl >/dev/null && localectl set-locale "LANG=$want" 2>/dev/null; then
        :
    elif command -v update-locale >/dev/null; then
        update-locale "LANG=$want"
    else
        echo "LANG=$want" > /etc/locale.conf
    fi
    [[ -f /etc/default/locale ]] && ! grep -q "^LANG=$want" /etc/default/locale \
        && sed -i "s/^LANG=.*/LANG=$want/" /etc/default/locale
    return 0
}

# --------------------------------------------------------------------------
# Запуск модуля отдельно / Standalone module run
#   sudo bash modules/22-timezone.sh
# --------------------------------------------------------------------------

ls_standalone() {
    [[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"
    mkdir -p "$LS_STATE_DIR"
    local rc
    step "$(basename "$0" .sh)"
    module_run; rc=$?
    (( rc == 0 )) && mark_done "$(basename "$0" .sh | sed 's/^[0-9]*-//')"
    exit $rc
}

detect_os

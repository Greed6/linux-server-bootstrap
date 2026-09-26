#!/usr/bin/env bash
# @group   ssh
# @title   Нестандартный порт SSH | Non-standard SSH port
# @default off
# @os      all

selinux_allow_port() {
    local port=$1
    selinux_enabled || return 0
    if ! command -v semanage >/dev/null; then
        pkg_install policycoreutils-python-utils >/dev/null 2>&1 || pkg_install policycoreutils-python >/dev/null 2>&1
    fi
    semanage port -a -t ssh_port_t -p tcp "$port" 2>/dev/null \
        || semanage port -m -t ssh_port_t -p tcp "$port" 2>/dev/null \
        || { err "SELinux: semanage port $port failed"; return 1; }
    info "SELinux: ssh_port_t += $port"
}

module_run() {
    local port cur keep=0 content files=() f fw
    cur=$(sshd_ports)
    info "$(L 'Сейчас SSH слушает порт(ы)' 'SSH currently listens on port(s)'): $cur"

    ask port SSH_PORT "$(L 'Новый порт SSH' 'New SSH port')" "2222"
    if [[ ! $port =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        err "$(L 'Некорректный порт' 'Invalid port'): $port"; return 1
    fi
    if [[ $port == 22 ]]; then
        info "$(L 'Порт 22 — стандартный, менять нечего' 'Port 22 is the default, nothing to change')"
        return 0
    fi
    if [[ " $cur " != *" $port "* ]] && ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$port$"; then
        err "$(L "Порт $port уже занят другой программой" "Port $port is already in use")"; return 1
    fi
    ask_yn SSH_KEEP_22 "$(L 'Оставить и порт 22, пока не проверите вход по новому? (рекомендуется)' \
                           'Keep port 22 too until you test the new one? (recommended)')" y && keep=1

    selinux_allow_port "$port" || return 1
    # Сначала открываем порт в файрволе, потом перезапускаем sshd
    fw_allow "$port" tcp "SSH"

    # Port накапливается из всех файлов — убираем чужие директивы Port
    for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
        [[ -f $f && $f != */00-linux-start-port.conf ]] && grep -qiE '^\s*Port\s' "$f" && files+=("$f")
    done
    backup "${files[@]}"
    ((${#files[@]})) && sed -i -E 's/^(\s*[Pp]ort\s)/# linux-start: \1/' "${files[@]}"

    content="Port $port"
    (( keep )) && content=$'Port 22\n'"Port $port"
    if ! sshd_write_block port "$content"; then
        restore "${files[@]}"
        sshd_restart
        return 1
    fi

    # fail2ban должен следить за актуальными портами
    if [[ -f /etc/fail2ban/jail.local ]] && grep -q 'linux-start' /etc/fail2ban/jail.local; then
        sed -i -E "/^\[sshd\]/,/^\[/ s/^port\s*=.*/port    = $(sshd_ports | tr ' ' ',')/" /etc/fail2ban/jail.local
        svc_active fail2ban && systemctl restart fail2ban
    fi

    if (( ! keep )); then
        fw=$(detect_fw)
        if [[ -n $fw ]] && ask_yn SSH_CLOSE_22 "$(L 'Закрыть порт 22 в файрволе?' 'Close port 22 in the firewall?')" n; then
            case $fw in
                ufw)       ufw delete allow 22/tcp >/dev/null 2>&1 ;;
                firewalld) firewall-cmd --permanent --remove-service=ssh >/dev/null && firewall-cmd --reload >/dev/null ;;
            esac
            summary "$(L 'Порт 22 закрыт в файрволе' 'Port 22 closed in the firewall')"
        fi
    fi

    summary "SSH $(L 'порт(ы)' 'port(s)'): $(sshd_ports)"
    warn "$(L "Проверьте в НОВОМ окне: ssh -p $port <user>@<host>. Текущую сессию не закрывайте." \
              "Test in a NEW window: ssh -p $port <user>@<host>. Keep this session open.")"
    (( keep )) && info "$(L 'Когда проверите — запустите модуль снова и ответьте «нет» на вопрос про порт 22.' \
                           'Once tested, run this module again and answer "no" about port 22.')"
    return 0
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

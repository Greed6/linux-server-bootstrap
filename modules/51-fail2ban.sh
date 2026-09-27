#!/usr/bin/env bash
# @group     security
# @title     fail2ban (защита SSH от перебора) | fail2ban (SSH brute-force protection)
# @default   on
# @os        all
# @conflicts crowdsec

module_run() {
    local backend=auto banaction="" trusted my_ip ports
    if ! pkg_ensure fail2ban; then
        err "$(L 'fail2ban недоступен (для RHEL-семейства нужен EPEL)' 'fail2ban is unavailable (RHEL family needs EPEL)')"
        return 1
    fi

    # Debian 12+ и минимальные установки пишут логи только в journald
    if [[ ! -f /var/log/auth.log && ! -f /var/log/secure ]]; then
        backend=systemd
        pkg_ensure python3-systemd >/dev/null 2>&1
    fi
    case $(detect_fw) in
        ufw)       banaction=ufw ;;
        firewalld) banaction=firewallcmd-rich-rules ;;
    esac

    # В сборке fail2ban из EPEL нет действия ufw — добавляем своё
    if [[ $banaction == ufw && ! -f /etc/fail2ban/action.d/ufw.conf ]]; then
        cat > /etc/fail2ban/action.d/ufw.conf <<'EOF'
# linux-start: ufw action (missing in EPEL fail2ban)
# prepend ставит правило первым и для IPv4, и для IPv6 (ufw >= 0.36);
# в EPEL 8 ufw 0.35 — там insert 1
[Definition]
actionstart =
actionstop =
actioncheck =
actionban   = ufw prepend deny from <ip> to any comment "fail2ban" || ufw insert 1 deny from <ip> to any
actionunban = ufw delete deny from <ip> to any
EOF
        info "$(L 'Добавлено действие fail2ban для ufw' 'Added fail2ban ufw action')"
    fi

    my_ip=${SSH_CLIENT:-}; my_ip=${my_ip%% *}
    ask trusted TRUSTED_IPS "$(L "Доверенные IP/подсети через пробел — их не банить${my_ip:+ (ваш IP: $my_ip)}" \
                                 "Trusted IPs/subnets, space separated — never banned${my_ip:+ (your IP: $my_ip)}")" ""
    ports=$(sshd_ports | tr ' ' ',')

    backup /etc/fail2ban/jail.local
    cat > /etc/fail2ban/jail.local <<EOF
# linux-start
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 ${trusted}
bantime  = 1h
findtime = 10m
maxretry = 5
bantime.increment = true
bantime.maxtime   = 1w
${banaction:+banaction = $banaction}
${banaction:+banaction_allports = $banaction}

[sshd]
enabled = true
port    = ${ports}
backend = ${backend}
EOF
    svc_enable_now fail2ban || return 1
    sleep 2
    fail2ban-client status sshd 2>/dev/null \
        || { err "$(L 'fail2ban не запустился, см. journalctl -u fail2ban' 'fail2ban did not start, see journalctl -u fail2ban')"; return 1; }
    summary "fail2ban: sshd ($ports), $(L 'бан 1ч с нарастанием до 1 недели' '1h ban increasing up to 1 week')${banaction:+, $banaction}"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

#!/usr/bin/env bash
# @group   security
# @title   Файрвол ufw (открыт только SSH, IPv4+IPv6) | ufw firewall (SSH only, IPv4+IPv6)
# @default on
# @os      all

setup_firewalld() {
    local p
    pkg_ensure firewalld || return 1
    svc_enable_now firewalld || return 1
    for p in $(sshd_ports); do
        firewall-cmd --permanent --add-port="$p/tcp" >/dev/null
    done
    firewall-cmd --reload >/dev/null
    summary "firewalld: $(L 'включён, SSH' 'enabled, SSH'): $(sshd_ports)"
}

module_run() {
    local p ports
    if ! pkg_ensure ufw; then
        warn "$(L 'ufw недоступен в репозиториях' 'ufw is not available in repositories')"
        if [[ $FAMILY == rhel ]] && ask_yn FIREWALLD_FALLBACK "$(L 'Использовать firewalld вместо ufw?' 'Use firewalld instead of ufw?')" y; then
            setup_firewalld; return
        fi
        return 1
    fi

    # ufw и firewalld не должны работать одновременно
    if svc_active firewalld; then
        svc_disable_now firewalld
        info "$(L 'firewalld отключён (конфликтует с ufw)' 'firewalld disabled (conflicts with ufw)')"
    fi

    backup /etc/default/ufw
    if grep -q '^IPV6=' /etc/default/ufw 2>/dev/null; then
        sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
    else
        echo "IPV6=yes" >> /etc/default/ufw
    fi

    # ufw из EPEL поставляется с разрешённым mDNS — оставляем только SSH
    local n
    while n=$(ufw status numbered 2>/dev/null | awk -F'[][]' '/mDNS/ {gsub(/ /, "", $2); print $2; exit}'); [[ -n $n ]]; do
        ufw --force delete "$n" >/dev/null || break
    done

    ufw default deny incoming  >/dev/null
    ufw default allow outgoing >/dev/null
    # Открываем все порты, на которых реально слушает sshd (22 и/или нестандартный)
    ports=$(sshd_ports)
    for p in $ports; do
        ufw allow "$p/tcp" comment "SSH" >/dev/null 2>&1 || ufw allow "$p/tcp" >/dev/null
    done
    if ! ufw --force enable; then
        err "$(L 'ufw не включился (в контейнере нет iptables/прав?)' 'ufw failed to enable (no iptables/privileges in a container?)')"
        return 1
    fi
    has_systemd && systemctl enable ufw >/dev/null 2>&1
    ufw status verbose
    summary "ufw: deny incoming, IPv4+IPv6, $(L 'открыт SSH' 'SSH allowed'): $ports/tcp"
    if command -v docker >/dev/null; then
        warn "$(L 'Docker публикует порты в обход ufw — учитывайте это (см. README)' 'Docker publishes ports bypassing ufw — keep that in mind (see README)')"
    fi
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

#!/usr/bin/env bash
# @group   system
# @title   Имя сервера (hostname, /etc/hosts) | Server name (hostname, /etc/hosts)
# @default on
# @os      all

module_run() {
    local current fqdn short
    current=$(hostname -f 2>/dev/null || hostname)
    ask fqdn HOSTNAME "$(L 'Имя сервера (можно FQDN: srv1.example.ru)' 'Server name (FQDN allowed: srv1.example.com)')" "$current"

    if [[ ! $fqdn =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        err "$(L 'Недопустимое имя' 'Invalid name'): $fqdn"
        return 1
    fi
    short=${fqdn%%.*}

    if command -v hostnamectl >/dev/null && hostnamectl set-hostname "$fqdn" 2>/dev/null; then
        :
    else
        echo "$fqdn" > /etc/hostname
        hostname "$fqdn" 2>/dev/null
    fi

    backup /etc/hosts
    # Убираем старую строку 127.0.1.1 и прописываем новое имя
    sed -i -E '/^127\.0\.1\.1\s/d' /etc/hosts
    if [[ $fqdn == "$short" ]]; then
        echo "127.0.1.1 $short" >> /etc/hosts
    else
        echo "127.0.1.1 $fqdn $short" >> /etc/hosts
    fi

    # cloud-init иначе вернёт старое имя при перезагрузке
    if [[ -d /etc/cloud/cloud.cfg.d ]]; then
        echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99-linux-start-hostname.cfg
        info "cloud-init: preserve_hostname: true"
    fi
    summary "$(L 'Имя сервера' 'Hostname'): $fqdn"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

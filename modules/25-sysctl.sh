#!/usr/bin/env bash
# @group   system
# @title   Сетевая безопасность ядра (sysctl) | Kernel network hardening (sysctl)
# @default on
# @os      all

# ip_forward не трогаем — он нужен Docker, VPN и маршрутизаторам.
SYSCTL_SETTINGS=(
    "net.ipv4.tcp_syncookies = 1"
    "net.ipv4.conf.all.rp_filter = 2"          # loose: безопасно и для нескольких интерфейсов
    "net.ipv4.conf.default.rp_filter = 2"
    "net.ipv4.conf.all.accept_redirects = 0"
    "net.ipv4.conf.default.accept_redirects = 0"
    "net.ipv4.conf.all.secure_redirects = 0"
    "net.ipv4.conf.default.secure_redirects = 0"
    "net.ipv6.conf.all.accept_redirects = 0"
    "net.ipv6.conf.default.accept_redirects = 0"
    "net.ipv4.conf.all.send_redirects = 0"
    "net.ipv4.conf.default.send_redirects = 0"
    "net.ipv4.conf.all.accept_source_route = 0"
    "net.ipv4.conf.default.accept_source_route = 0"
    "net.ipv6.conf.all.accept_source_route = 0"
    "net.ipv6.conf.default.accept_source_route = 0"
    "net.ipv4.conf.all.log_martians = 1"
    "net.ipv4.icmp_echo_ignore_broadcasts = 1"
    "net.ipv4.icmp_ignore_bogus_error_responses = 1"
    "kernel.kptr_restrict = 2"
    "kernel.dmesg_restrict = 1"
    "kernel.randomize_va_space = 2"
    "fs.protected_hardlinks = 1"
    "fs.protected_symlinks = 1"
)

module_run() {
    local conf=/etc/sysctl.d/90-linux-start.conf line key path n=0
    backup "$conf"
    mkdir -p /etc/sysctl.d
    {
        echo "# linux-start: kernel network hardening"
        for line in "${SYSCTL_SETTINGS[@]}"; do
            line=${line%%#*}; line=${line%"${line##*[![:space:]]}"}
            key=${line%% *}
            path=/proc/sys/${key//.//}
            # Пропускаем параметры, которых нет в этом ядре
            [[ -e $path ]] || continue
            echo "$line"
            n=$((n + 1))
        done
    } > "$conf"
    sysctl -q -p "$conf" 2>&1 | grep -v 'Read-only' || true
    summary "sysctl: $n $(L 'параметров в' 'settings in') $conf"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

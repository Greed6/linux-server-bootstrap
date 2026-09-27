#!/usr/bin/env bash
# @group   repos
# @title   Автообновления безопасности | Automatic security updates
# @default on
# @os      all

auto_updates_debian() {
    local reboot=false rtime=""
    pkg_ensure unattended-upgrades || return 1
    backup /etc/apt/apt.conf.d/20auto-upgrades
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
// linux-start
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    # По умолчанию 50unattended-upgrades ставит только обновления безопасности
    if ask_yn AUTO_REBOOT "$(L 'Разрешить автоматическую перезагрузку, если она требуется?' 'Allow automatic reboot when required?')" n; then
        ask rtime AUTO_REBOOT_TIME "$(L 'Время перезагрузки' 'Reboot time')" "04:00"
        reboot=true
    fi
    cat > /etc/apt/apt.conf.d/52linux-start-unattended <<EOF
// linux-start
Unattended-Upgrade::Automatic-Reboot "${reboot}";
${rtime:+Unattended-Upgrade::Automatic-Reboot-Time "$rtime";}
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
    svc_enable_now unattended-upgrades
    summary "unattended-upgrades: $(L 'только обновления безопасности' 'security updates only'), $(L 'автоперезагрузка' 'auto-reboot'): $reboot"
}

auto_updates_rhel() {
    local type=security
    # В CentOS нет security-метаданных — «security» там ничего не поставит
    if [[ $OS_ID == centos ]]; then
        warn "$(L "$OS_ID не публикует метаданные безопасности — будут ставиться все обновления" \
                  "$OS_ID does not publish security metadata — all updates will be applied")"
        type=default
    fi

    pkg_ensure dnf-automatic || return 1
    local conf=/etc/dnf/automatic.conf
    backup "$conf"
    sed -i -E "s/^upgrade_type\s*=.*/upgrade_type = ${type}/; s/^apply_updates\s*=.*/apply_updates = yes/" "$conf"
    has_systemd && systemctl enable --now dnf-automatic.timer
    summary "$(L 'Автообновления' 'Automatic updates'): $PKG ($type)"
}

module_run() {
    if [[ $FAMILY == debian ]]; then auto_updates_debian; else auto_updates_rhel; fi
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

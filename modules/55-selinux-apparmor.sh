#!/usr/bin/env bash
# @group   security
# @title   Проверка SELinux / AppArmor (только отчёт) | SELinux / AppArmor check (report only)
# @default on
# @os      all

# Модуль ничего не меняет: отключать SELinux/AppArmor — плохая практика.
module_run() {
    local found=0 mode
    if command -v getenforce >/dev/null; then
        found=1
        mode=$(getenforce 2>/dev/null)
        case $mode in
            Enforcing)  ok "SELinux: Enforcing" ;;
            Permissive) warn "SELinux: Permissive — $(L 'нарушения только логируются' 'violations are only logged')" ;;
            *)          warn "SELinux: ${mode:-Disabled} — $(L 'защита выключена' 'protection is off')" ;;
        esac
        summary "SELinux: ${mode:-unknown}"
    fi
    if command -v aa-status >/dev/null || [[ -d /sys/kernel/security/apparmor ]]; then
        found=1
        if aa-status --enabled 2>/dev/null; then
            ok "AppArmor: $(L 'включён' 'enabled'), $(aa-status 2>/dev/null | sed -n 's/^\([0-9]*\) profiles are in enforce mode.*/\1/p') enforce"
            summary "AppArmor: enabled"
        else
            warn "AppArmor: $(L 'выключен' 'disabled')"
            summary "AppArmor: disabled"
        fi
    fi
    (( found )) || info "$(L 'SELinux/AppArmor не обнаружены' 'SELinux/AppArmor not found')"
    return 0
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

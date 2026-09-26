#!/usr/bin/env bash
# @group   security
# @title   Astra: уровень защищённости, МКЦ, ЗПС (отчёт) | Astra: security level, MIC, DigSig (report)
# @default on
# @os      astra

# Только отчёт: включение МКЦ/ЗПС требует планирования и перезагрузки.
module_run() {
    local cmd out
    if command -v astra-modeswitch >/dev/null; then
        out=$(astra-modeswitch getname 2>/dev/null)
        info "$(L 'Уровень защищённости' 'Security level'): ${out:-?}"
        summary "Astra $(L 'уровень' 'level'): ${out:-?}"
    fi
    for cmd in astra-mic-control astra-digsig-control astra-mac-control astra-ptrace-lock astra-swapwiper-control; do
        command -v "$cmd" >/dev/null || continue
        out=$($cmd status 2>/dev/null | head -n1)
        printf '  %-26s %s\n' "$cmd" "${out:-?}"
    done
    info "$(L 'МКЦ — мандатный контроль целостности, ЗПС — замкнутая программная среда (astra-digsig-control).' \
              'MIC — mandatory integrity control, DigSig — closed software environment (astra-digsig-control).')"
    return 0
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

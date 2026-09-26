#!/usr/bin/env bash
# @group   system
# @title   Синхронизация времени NTP (chrony) | Time sync NTP (chrony)
# @default on
# @os      all

module_run() {
    local servers conf svc s f
    ask servers NTP_SERVERS "$(L 'NTP-серверы через пробел' 'NTP servers, space separated')" "ru.pool.ntp.org"
    [[ -z $servers ]] && { err "$(L 'Не указан NTP-сервер' 'No NTP server given')"; return 1; }

    # Одновременно должен работать только один NTP-клиент
    for s in systemd-timesyncd ntp ntpd; do
        if svc_active "$s"; then
            svc_disable_now "$s"
            info "$(L "Отключён $s" "Disabled $s")"
        fi
    done

    pkg_ensure chrony || { err "$(L 'Не удалось установить chrony' 'Failed to install chrony')"; return 1; }

    if [[ -f /etc/chrony/chrony.conf ]]; then conf=/etc/chrony/chrony.conf; else conf=/etc/chrony.conf; fi
    svc=chronyd; svc_exists chrony && svc=chrony

    backup "$conf" /etc/chrony/sources.d/*.sources
    # Комментируем штатные server/pool (в т.ч. Ubuntu sources.d)
    sed -i -E 's/^(\s*(server|pool)\s)/# linux-start: \1/' "$conf"
    for f in /etc/chrony/sources.d/*.sources; do
        [[ -f $f ]] && sed -i -E 's/^(\s*(server|pool)\s)/# linux-start: \1/' "$f"
    done
    sed -i '/^# >>> linux-start/,/^# <<< linux-start/d' "$conf"
    {
        echo "# >>> linux-start"
        for s in $servers; do
            if [[ $s == *pool* ]]; then echo "pool $s iburst"; else echo "server $s iburst"; fi
        done
        grep -qE '^\s*makestep' "$conf" || echo "makestep 1.0 3"
        echo "# <<< linux-start"
    } >> "$conf"

    if svc_enable_now "$svc"; then
        sleep 3
        chronyc -a makestep >/dev/null 2>&1
        chronyc sources 2>/dev/null
    fi
    summary "NTP (chrony): $servers"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

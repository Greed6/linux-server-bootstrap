#!/usr/bin/env bash
# @group   system
# @title   Журнал systemd: хранение и лимит | systemd journal: storage and limit
# @default on
# @os      all

module_run() {
    local size keep dir=/etc/systemd/journald.conf.d
    ask size JOURNAL_MAX_SIZE "$(L 'Максимальный размер журнала' 'Maximum journal size')" "500M"
    ask keep JOURNAL_RETENTION "$(L 'Хранить записи не дольше' 'Keep entries for at most')" "1month"
    [[ $size =~ ^[0-9]+[KMG]$ ]] || { err "$(L 'Формат размера: 500M, 1G' 'Size format: 500M, 1G')"; return 1; }

    mkdir -p "$dir"
    cat > "$dir/90-linux-start.conf" <<EOF
# linux-start
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=${size}
MaxRetentionSec=${keep}
EOF
    # Постоянное хранение: журнал переживает перезагрузку
    mkdir -p /var/log/journal
    command -v systemd-tmpfiles >/dev/null && systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null
    has_systemd && systemctl restart systemd-journald
    summary "journald: persistent, SystemMaxUse=$size, MaxRetentionSec=$keep"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

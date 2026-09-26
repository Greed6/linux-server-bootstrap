#!/usr/bin/env bash
# @group   security
# @title   Аудит изменений (auditd) | Change auditing (auditd)
# @default off
# @os      all

module_run() {
    local pkg=audit rules=/etc/audit/rules.d/90-linux-start.rules
    [[ $FAMILY == debian ]] && pkg=auditd
    pkg_ensure "$pkg" || return 1

    mkdir -p /etc/audit/rules.d
    cat > "$rules" <<'EOF'
## linux-start: базовые правила / basic rules
## Поиск событий / search:  ausearch -k identity | ausearch -k sudoers ...

# Учётные записи и группы / accounts and groups
-w /etc/passwd  -p wa -k identity
-w /etc/shadow  -p wa -k identity
-w /etc/group   -p wa -k identity
-w /etc/gshadow -p wa -k identity

# sudo
-w /etc/sudoers   -p wa -k sudoers
-w /etc/sudoers.d -p wa -k sudoers

# SSH
-w /etc/ssh/sshd_config   -p wa -k sshd
-w /etc/ssh/sshd_config.d -p wa -k sshd

# Планировщик / scheduler
-w /etc/crontab      -p wa -k cron
-w /etc/cron.d       -p wa -k cron
-w /var/spool/cron   -p wa -k cron

# Время / time
-w /etc/localtime -p wa -k time-change

# Модули ядра / kernel modules
-w /sbin/insmod   -p x -k modules
-w /sbin/modprobe -p x -k modules
EOF
    chmod 640 "$rules"
    has_systemd && systemctl enable auditd >/dev/null 2>&1
    # auditd запрещает systemctl restart — правила грузим через augenrules
    if command -v augenrules >/dev/null; then
        augenrules --load >/dev/null 2>&1 || service auditd restart >/dev/null 2>&1
    else
        service auditd restart >/dev/null 2>&1
    fi
    svc_active auditd || { has_systemd && systemctl start auditd 2>/dev/null; }
    summary "auditd: $(L 'правила в' 'rules in') $rules"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

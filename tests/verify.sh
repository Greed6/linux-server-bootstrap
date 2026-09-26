#!/usr/bin/env bash
# Проверки после прогона внутри контейнера / post-run checks inside a container
# Проверяются только модули из LS_TEST_MODULES (или набора по умолчанию).

set -u
MODS=" ${LS_TEST_MODULES:-repos auto-updates timezone ntp sysctl journald base-tools nano mc micro ssh-keys ssh-port ssh-hardening ufw fail2ban selinux-apparmor} "
pass=0 fail=0

check() {
    local name=$1; shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS  $name"; pass=$((pass + 1))
    else
        echo "  FAIL  $name"; fail=$((fail + 1))
    fi
}
has() { [[ $MODS == *" $1 "* ]]; }

check "locale ru_RU.UTF-8"           bash -c 'locale -a | grep -qiE "^ru_RU\.utf-?8$"'
has repos && check "repos: no plain http" bash -c '! grep -rhsE "^[^#]*http://" /etc/apt/sources.list /etc/apt/sources.list.d/ /etc/yum.repos.d/ | grep -vE "^\s*(#|gpgkey)"'
has timezone && check "timezone Europe/Moscow" bash -c 'readlink -f /etc/localtime | grep -q Europe/Moscow'
has ntp && check "chrony configured"  bash -c 'grep -qs "ru.pool.ntp.org" /etc/chrony.conf /etc/chrony/chrony.conf'
has ntp && check "chrony running"     bash -c 'systemctl is-active chrony || systemctl is-active chronyd'
has sysctl && check "sysctl file"     test -s /etc/sysctl.d/90-linux-start.conf
has journald && check "journald conf" grep -q SystemMaxUse=200M /etc/systemd/journald.conf.d/90-linux-start.conf
has base-tools && check "jq installed" command -v jq
has nano && check "nano"              command -v nano
has mc && check "mc"                  command -v mc
has micro && check "micro"            command -v micro
has auto-updates && check "auto-updates" bash -c 'test -f /etc/apt/apt.conf.d/20auto-upgrades || systemctl is-enabled dnf-automatic.timer || systemctl is-enabled yum-cron'
if has ssh-keys; then
    check "user admin exists"         id admin
    check "admin authorized_keys"     grep -q ssh-ed25519 /home/admin/.ssh/authorized_keys
    check "authorized_keys mode 600"  bash -c '[[ $(stat -c %a /home/admin/.ssh/authorized_keys) == 600 ]]'
fi
if has ssh-hardening; then
    check "sshd: passwordauthentication no" bash -c 'mkdir -p /run/sshd; $(command -v sshd || echo /usr/sbin/sshd) -T | grep -qx "passwordauthentication no"'
    check "sshd: permitrootlogin no"        bash -c 'mkdir -p /run/sshd; $(command -v sshd || echo /usr/sbin/sshd) -T | grep -qx "permitrootlogin no"'
    check "sshd running"                    bash -c 'systemctl is-active ssh || systemctl is-active sshd'
fi
if has ssh-port; then
    check "sshd: port 2222"  bash -c 'mkdir -p /run/sshd; $(command -v sshd || echo /usr/sbin/sshd) -T | grep -qx "port 2222"'
    check "sshd: port 22"    bash -c 'mkdir -p /run/sshd; $(command -v sshd || echo /usr/sbin/sshd) -T | grep -qx "port 22"'
    check "listening 2222"   bash -c 'ss -ltn | grep -qE "[:.]2222\s"'
fi
if has ufw; then
    if command -v ufw >/dev/null; then
        check "ufw active"       bash -c 'ufw status | grep -q "Status: active"'
        check "ufw 22/tcp v4+v6" bash -c 'ufw status | grep -qE "^22/tcp\s+ALLOW" && ufw status | grep -qE "^22/tcp \(v6\)\s+ALLOW"'
        has ssh-port && check "ufw 2222/tcp" bash -c 'ufw status | grep -qE "^2222/tcp\s+ALLOW"'
    else
        check "firewalld active" systemctl is-active firewalld
    fi
fi
has fail2ban && check "fail2ban sshd jail" fail2ban-client status sshd
if has crowdsec; then
    check "crowdsec running"   systemctl is-active crowdsec
    check "crowdsec LAPI 8081" bash -c 'ss -ltn | grep -qE "0\.0\.0\.0:8081\s"'
    check "bouncer registered" bash -c 'cscli bouncers list | grep -q firewall'
fi

echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))

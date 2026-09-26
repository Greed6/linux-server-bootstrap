#!/usr/bin/env bash
# @group     security
# @title     CrowdSec (защита + общий чёрный список) | CrowdSec (protection + shared blocklist)
# @default   off
# @os        all
# @conflicts fail2ban

add_crowdsec_repo() {
    local tmp os="" dist=""
    # Установщик репозитория не знает Astra и РЕД ОС — подсказываем базовый дистрибутив
    case $OS_ID in
        astra) os=debian; if [[ $OS_VER == 1.8* ]]; then dist=bookworm; else dist=buster; fi ;;
        redos) os=rhel; if (( OS_MAJOR >= 8 )); then dist=9; else dist=7; fi ;;
        # rocky, almalinux, ol, rhel, centos, debian, ubuntu установщик определяет сам
    esac
    tmp=$(mktemp)
    if ! curl -fsSL --max-time 30 https://install.crowdsec.net -o "$tmp"; then
        rm -f "$tmp"; return 1
    fi
    if [[ -n $os ]]; then os=$os dist=$dist bash "$tmp"; else bash "$tmp"; fi
    local rc=$?
    rm -f "$tmp"
    return $rc
}

module_run() {
    local port bind=127.0.0.1 external=0 bouncer bconf
    pkg_ensure curl >/dev/null 2>&1
    if ! pkg_installed crowdsec; then
        add_crowdsec_repo || { err "$(L 'Не удалось подключить репозиторий CrowdSec' 'Failed to add the CrowdSec repository')"; return 1; }
        pkg_install crowdsec || { err "$(L 'Не удалось установить crowdsec' 'Failed to install crowdsec')"; return 1; }
    fi

    # Логи SSH из journald, если нет классических файлов
    if [[ ! -f /var/log/auth.log && ! -f /var/log/secure ]]; then
        mkdir -p /etc/crowdsec/acquis.d
        cat > /etc/crowdsec/acquis.d/linux-start-sshd.yaml <<EOF
source: journalctl
journalctl_filter:
  - "_SYSTEMD_UNIT=${SSH_SVC}.service"
labels:
  type: syslog
EOF
    fi
    cscli collections install crowdsecurity/linux crowdsecurity/sshd >/dev/null 2>&1

    # --- порт LAPI: API, к которому подключаются агенты/баунсеры других серверов ---
    ask port CROWDSEC_LAPI_PORT "$(L 'Порт CrowdSec LAPI (API чёрного списка)' 'CrowdSec LAPI port (blocklist API)')" "8080"
    [[ $port =~ ^[0-9]+$ ]] && (( port > 0 && port < 65536 )) || port=8080
    if ask_yn CROWDSEC_LAPI_EXTERNAL "$(L 'Открыть LAPI для других серверов (центральный чёрный список) и добавить порт в файрвол?' \
                                          'Expose LAPI to other servers (central blocklist) and add the port to the firewall?')" n; then
        bind=0.0.0.0; external=1
    fi

    backup /etc/crowdsec/config.yaml /etc/crowdsec/local_api_credentials.yaml
    sed -i -E "s|^(\s*listen_uri:).*|\1 ${bind}:${port}|" /etc/crowdsec/config.yaml
    sed -i -E "s|^(url:).*|\1 http://127.0.0.1:${port}|" /etc/crowdsec/local_api_credentials.yaml
    svc_enable_now crowdsec || return 1
    sleep 3

    # --- баунсер: реальная блокировка в файрволе ---
    bouncer=crowdsec-firewall-bouncer-iptables
    [[ $(detect_fw) == firewalld ]] && bouncer=crowdsec-firewall-bouncer-nftables
    if pkg_ensure "$bouncer"; then
        bconf=/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
        [[ -f $bconf ]] && sed -i -E "s|^(api_url:).*|\1 http://127.0.0.1:${port}/|" "$bconf"
        svc_enable_now crowdsec-firewall-bouncer
    else
        warn "$(L "Не удалось установить $bouncer — CrowdSec будет только обнаруживать атаки, но не блокировать" \
                  "Failed to install $bouncer — CrowdSec will detect attacks but not block them")"
    fi

    (( external )) && fw_allow "$port" tcp "CrowdSec LAPI"
    cscli bouncers list 2>/dev/null
    summary "CrowdSec: LAPI ${bind}:${port}, $(L 'баунсер' 'bouncer') $bouncer"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

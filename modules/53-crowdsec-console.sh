#!/usr/bin/env bash
# @group   security
# @title   Подключить CrowdSec к консоли app.crowdsec.net | Enroll CrowdSec to app.crowdsec.net console
# @default off
# @os      all

module_run() {
    local key name
    if ! command -v cscli >/dev/null; then
        err "$(L 'CrowdSec не установлен — сначала модуль «CrowdSec»' 'CrowdSec is not installed — run the "CrowdSec" module first')"
        return 1
    fi
    info "$(L 'Ключ: app.crowdsec.net → Security Engines → Enroll command' 'Key: app.crowdsec.net → Security Engines → Enroll command')"
    ask_secret key CROWDSEC_ENROLL_KEY "$(L 'Ключ подключения (enroll key)' 'Enroll key')"
    [[ -z $key ]] && { err "$(L 'Ключ не указан' 'No key given')"; return 1; }
    ask name CROWDSEC_ENROLL_NAME "$(L 'Имя сервера в консоли' 'Name in the console')" "$(hostname)"

    cscli console enroll -e context --name "$name" "$key" || return 1
    has_systemd && systemctl restart crowdsec
    summary "CrowdSec console: $(L 'заявка отправлена — подтвердите её на app.crowdsec.net' 'enrollment sent — accept it on app.crowdsec.net')"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

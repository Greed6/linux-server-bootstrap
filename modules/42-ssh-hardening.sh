#!/usr/bin/env bash
# @group   ssh
# @title   Вход по SSH только по ключу | SSH key-only login
# @default on
# @os      all

# Печатает пользователей, у которых есть хотя бы один ключ
users_with_keys() {
    local name home shell ak
    while IFS=: read -r name _ _ _ _ home shell; do
        [[ $shell == */nologin || $shell == */false ]] && continue
        ak="$home/.ssh/authorized_keys"
        [[ -f $ak ]] && grep -qE '^(ssh-|ecdsa-|sk-)' "$ak" && echo "$name"
    done < <(getent passwd)
}

module_run() {
    local keyed root_login=prohibit-password kbd_opt content
    keyed=$(users_with_keys | tr '\n' ' ')
    if [[ -z $keyed ]]; then
        err "$(L 'Ни у одного пользователя нет SSH-ключа — вход по паролю НЕ отключаю (иначе потеряете доступ). Сначала выполните «SSH-сервер, пользователь и ключ».' \
                 'No user has an SSH key — NOT disabling password login (you would lose access). Run "SSH server, user and key" first.')"
        return 1
    fi
    info "$(L 'Ключи есть у' 'Keys found for'): $keyed"

    # root по паролю запрещён всегда; полностью — если есть другой пользователь с ключом
    if [[ $keyed != "root " ]]; then
        ask_yn SSH_DISABLE_ROOT "$(L 'Полностью запретить вход под root по SSH?' 'Completely disable root login over SSH?')" y \
            && root_login=no
    fi

    if (( $(ssh_version) >= 87 )); then kbd_opt=KbdInteractiveAuthentication; else kbd_opt=ChallengeResponseAuthentication; fi
    content="PubkeyAuthentication yes
PasswordAuthentication no
${kbd_opt} no
PermitEmptyPasswords no
AuthenticationMethods publickey
PermitRootLogin ${root_login}
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2"

    sshd_write_block hardening "$content" || return 1
    summary "$(L "SSH: только ключи, PermitRootLogin $root_login" "SSH: keys only, PermitRootLogin $root_login")"
    warn "$(L 'НЕ закрывайте текущую сессию! Проверьте вход по ключу в новом окне.' \
              'Do NOT close this session! Test key login in a new window.')"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

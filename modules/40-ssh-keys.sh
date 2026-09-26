#!/usr/bin/env bash
# @group   ssh
# @title   SSH-сервер, пользователь и ключ | SSH server, user and key
# @default on
# @os      all

# add_keys_from <файл с ключами> <authorized_keys>
add_keys_from() {
    local src=$1 ak=$2 line tmp fp
    tmp=$(mktemp)
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        [[ -z $line || $line == \#* ]] && continue
        printf '%s\n' "$line" > "$tmp"
        if fp=$(ssh-keygen -l -f "$tmp" 2>/dev/null); then
            if grep -qxF "$line" "$ak"; then
                info "$(L 'Ключ уже есть' 'Key already present'): $fp"
            else
                printf '%s\n' "$line" >> "$ak"
                ok "$(L 'Добавлен ключ' 'Key added'): $fp"
            fi
        else
            warn "$(L 'Некорректный ключ, пропущен' 'Invalid key, skipped'): ${line:0:40}…"
        fi
    done < "$src"
    rm -f "$tmp"
}

create_user() {
    local user=$1 grp
    useradd -m -s /bin/bash "$user" || return 1
    grp=$(sudo_group)
    [[ -n $grp ]] && usermod -aG "$grp" "$user"
    if answer_get SSH_USER_PASSWORD >/dev/null; then
        echo "$user:$(answer_get SSH_USER_PASSWORD)" | chpasswd
    elif has_tty; then
        info "$(L "Задайте пароль для $user (нужен для sudo):" "Set a password for $user (needed for sudo):")"
        passwd "$user" </dev/tty >/dev/tty 2>&1
    else
        warn "$(L "Пароль не задан — выполните: passwd $user" "Password not set — run: passwd $user")"
    fi
    summary "$(L "Создан пользователь $user (группа ${grp:-—})" "User $user created (group ${grp:-—})")"
}

read_keys() {
    # Пишет ключи во временный файл $1
    local out=$1 c src line
    if src=$(answer_get SSH_KEYS); then
        printf '%s\n' "$src" > "$out"
    elif src=$(answer_get SSH_KEYS_URL); then
        curl -fsSL --max-time 15 "$src" -o "$out" || warn "$(L 'Не удалось скачать ключи' 'Failed to download keys')"
    elif src=$(answer_get SSH_KEYS_FILE); then
        cat "$src" > "$out" 2>/dev/null || warn "$(L 'Файл не читается' 'File is not readable')"
    elif has_tty; then
        echo "$(L 'Откуда взять публичный ключ?' 'Where to get the public key from?')"
        echo "  1) $(L 'Вставить вручную' 'Paste manually')"
        echo "  2) URL (https://github.com/<user>.keys)"
        echo "  3) $(L 'Файл на сервере' 'File on this server')"
        echo "  4) $(L 'Пропустить' 'Skip')"
        ask c SSH_KEY_SOURCE "$(L 'Выбор' 'Choice')" 1
        case $c in
            1)
                echo "$(L 'Вставьте ключ(и), затем пустую строку:' 'Paste key(s), then an empty line:')" >/dev/tty
                while IFS= read -r line </dev/tty; do
                    [[ -z $line ]] && break
                    printf '%s\n' "$line" >> "$out"
                done ;;
            2)
                ask src SSH_KEYS_URL "URL" ""
                [[ -n $src ]] && { curl -fsSL --max-time 15 "$src" -o "$out" \
                    || warn "$(L 'Не удалось скачать ключи' 'Failed to download keys')"; } ;;
            3)
                ask src SSH_KEYS_FILE "$(L 'Путь к файлу' 'File path')" ""
                cat "$src" > "$out" 2>/dev/null || warn "$(L 'Файл не читается' 'File is not readable')" ;;
        esac
    fi
    return 0
}

module_run() {
    local user home ak grp tmp nkeys
    pkg_ensure openssh-server || return 1
    command -v ssh-keygen >/dev/null || pkg_install openssh-client 2>/dev/null || pkg_install openssh-clients
    svc_enable_now "$SSH_SVC"

    ask user SSH_USER "$(L 'Пользователь, для которого добавить SSH-ключ' 'User to add the SSH key for')" "${SUDO_USER:-root}"
    if ! id -u "$user" >/dev/null 2>&1; then
        ask_yn SSH_CREATE_USER "$(L "Пользователя $user нет. Создать (с правами sudo)?" \
                                    "User $user does not exist. Create (with sudo rights)?")" y || return 1
        create_user "$user" || { err "useradd $user failed"; return 1; }
    fi

    home=$(getent passwd "$user" | cut -d: -f6)
    grp=$(id -gn "$user")
    ak="$home/.ssh/authorized_keys"
    install -d -m 700 -o "$user" -g "$grp" "$home/.ssh"
    touch "$ak"

    tmp=$(mktemp)
    read_keys "$tmp"
    [[ -s $tmp ]] && add_keys_from "$tmp" "$ak"
    rm -f "$tmp"

    chmod 600 "$ak"
    chown -R "$user:$grp" "$home/.ssh"
    command -v restorecon >/dev/null && restorecon -R "$home/.ssh" 2>/dev/null

    nkeys=$(grep -cE '^(ssh-|ecdsa-|sk-)' "$ak" 2>/dev/null)
    echo "$user" > "$LS_STATE_DIR/ssh_user"
    if (( ${nkeys:-0} == 0 )); then
        warn "$(L "В $ak нет ключей" "No keys in $ak")"
        return 1
    fi
    summary "$(L "SSH-ключей у $user" "SSH keys for $user"): $nkeys"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

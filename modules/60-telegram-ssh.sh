#!/usr/bin/env bash
# @group   notify
# @title   Уведомления о входе по SSH в Telegram | SSH login alerts to Telegram
# @default off
# @os      all

NOTIFY_BIN=/usr/local/sbin/linux-start-ssh-notify
NOTIFY_CONF=/etc/linux-start/telegram.conf

module_run() {
    local token chat pam=/etc/pam.d/sshd
    info "$(L 'Бот: @BotFather → /newbot. chat_id: напишите боту и откройте https://api.telegram.org/bot<TOKEN>/getUpdates' \
              'Bot: @BotFather → /newbot. chat_id: message the bot and open https://api.telegram.org/bot<TOKEN>/getUpdates')"
    ask_secret token TELEGRAM_BOT_TOKEN "Bot token"
    ask chat TELEGRAM_CHAT_ID "chat_id" ""
    [[ -z $token || -z $chat ]] && { err "$(L 'Нужны token и chat_id' 'token and chat_id are required')"; return 1; }
    pkg_ensure curl >/dev/null 2>&1

    install -d -m 700 /etc/linux-start
    ( umask 077; printf 'TG_TOKEN=%q\nTG_CHAT_ID=%q\n' "$token" "$chat" > "$NOTIFY_CONF" )

    cat > "$NOTIFY_BIN" <<'EOF'
#!/bin/sh
# linux-start: уведомление о входе по SSH / SSH login notification (pam_exec)
[ "$PAM_TYPE" = "open_session" ] || exit 0
. /etc/linux-start/telegram.conf
HOST=$(hostname -f 2>/dev/null || hostname)
TEXT="SSH login: ${PAM_USER}@${HOST}
from: ${PAM_RHOST:-unknown}
time: $(date '+%F %T %Z')"
curl -s --max-time 5 "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" --data-urlencode text="$TEXT" >/dev/null 2>&1 &
exit 0
EOF
    chmod 755 "$NOTIFY_BIN"

    backup "$pam"
    if ! grep -q "$NOTIFY_BIN" "$pam"; then
        echo "session optional pam_exec.so quiet $NOTIFY_BIN" >> "$pam"
    fi

    if ask_yn TELEGRAM_TEST "$(L 'Отправить тестовое сообщение?' 'Send a test message?')" y; then
        if curl -fsS --max-time 10 "https://api.telegram.org/bot${token}/sendMessage" \
            -d chat_id="$chat" --data-urlencode text="linux-start: $(hostname) — test" >/dev/null; then
            ok "$(L 'Сообщение отправлено' 'Message sent')"
        else
            err "$(L 'Telegram отклонил запрос — проверьте token и chat_id' 'Telegram rejected the request — check token and chat_id')"
            return 1
        fi
    fi
    summary "$(L 'Уведомления о входе по SSH → Telegram' 'SSH login alerts → Telegram') (chat $chat)"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

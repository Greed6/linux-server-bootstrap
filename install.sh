#!/usr/bin/env bash
#
# install.sh — скачать linux-server-bootstrap и запустить одной командой
#              download linux-server-bootstrap and run it with one command
#
#   curl -fsSL https://raw.githubusercontent.com/Greed6/linux-server-bootstrap/main/install.sh | sudo bash
#   wget -qO-  https://raw.githubusercontent.com/Greed6/linux-server-bootstrap/main/install.sh | sudo bash
#
# Аргументы после «bash -s --» передаются в linux-start.sh:
#   curl -fsSL .../install.sh | sudo bash -s -- --lang en --text-menu
#
# Переменные окружения / environment:
#   GITHUB_TOKEN   токен для приватного репозитория / token for a private repository
#   LS_REF         ветка или тег / branch or tag (main)
#   LS_DEST        куда установить / install directory (/opt/linux-server-bootstrap)
#
# Повторный запуск команды обновляет скрипт до последней версии.

set -euo pipefail

REPO="Greed6/linux-server-bootstrap"
REF=${LS_REF:-main}
DEST=${LS_DEST:-/opt/linux-server-bootstrap}
# Публичный архив не ограничен лимитом API (60 запросов в час с IP);
# с токеном (приватный репозиторий) — только через API
if [[ -n ${GITHUB_TOKEN:-} ]]; then
    URL=${LS_TARBALL_URL:-https://api.github.com/repos/$REPO/tarball/$REF}
else
    URL=${LS_TARBALL_URL:-https://github.com/$REPO/archive/$REF.tar.gz}
fi

die() { echo "[x] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Запустите от root / Run as root: curl -fsSL <url> | sudo bash"

fetch() {
    # fetch <url> <файл>
    local auth=()
    if command -v curl >/dev/null; then
        [[ -n ${GITHUB_TOKEN:-} ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
        curl -fsSL "${auth[@]}" "$1" -o "$2"
    elif command -v wget >/dev/null; then
        [[ -n ${GITHUB_TOKEN:-} ]] && auth=(--header="Authorization: Bearer $GITHUB_TOKEN")
        wget -q "${auth[@]}" "$1" -O "$2"
    else
        die "Нужен curl или wget / curl or wget is required"
    fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "[*] $REPO ($REF) → $DEST"
if ! fetch "$URL" "$tmp/src.tar.gz"; then
    die "Не удалось скачать $REPO. Для приватного репозитория задайте GITHUB_TOKEN. / Download failed. Set GITHUB_TOKEN for a private repository."
fi

mkdir -p "$tmp/src"
tar -xzf "$tmp/src.tar.gz" -C "$tmp/src" --strip-components=1
[[ -f $tmp/src/linux-start.sh ]] || die "В архиве нет linux-start.sh / linux-start.sh not found in the archive"

# Заменяем каталог целиком, чтобы удалённые модули не оставались
rm -rf "$DEST.new"
mv "$tmp/src" "$DEST.new"
rm -rf "$DEST"
mv "$DEST.new" "$DEST"
chmod +x "$DEST/linux-start.sh" "$DEST"/modules/*.sh

# Меню читает ответы из /dev/tty, поэтому работает и при запуске через pipe
exec bash "$DEST/linux-start.sh" "$@"

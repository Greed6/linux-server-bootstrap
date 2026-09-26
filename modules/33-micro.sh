#!/usr/bin/env bash
# @group   software
# @title   Редактор micro | micro editor
# @default on
# @os      all

install_micro_binary() {
    local suffix tag ver tmp
    case $(uname -m) in
        x86_64)  suffix=linux64 ;;
        aarch64) suffix=linux-arm64 ;;
        armv7l)  suffix=linux-arm ;;
        i?86)    suffix=linux32 ;;
        *) err "micro: unsupported arch $(uname -m)"; return 1 ;;
    esac
    command -v curl >/dev/null || pkg_install curl >/dev/null
    tag=$(curl -fsSL --max-time 15 https://api.github.com/repos/zyedidia/micro/releases/latest \
          | sed -nE 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/p')
    [[ -z $tag ]] && { err "micro: $(L 'не удалось узнать последнюю версию' 'cannot get the latest version')"; return 1; }
    ver=${tag#v}
    tmp=$(mktemp -d)
    if curl -fsSL --max-time 120 -o "$tmp/micro.tgz" \
        "https://github.com/zyedidia/micro/releases/download/${tag}/micro-${ver}-${suffix}.tar.gz"; then
        tar -xzf "$tmp/micro.tgz" -C "$tmp" && install -m 755 "$tmp/micro-${ver}/micro" /usr/local/bin/micro
    fi
    rm -rf "$tmp"
    command -v micro >/dev/null
}

module_run() {
    if command -v micro >/dev/null; then
        ok "micro $(L 'уже установлен' 'is already installed')"
        return 0
    fi
    if pkg_available micro && pkg_install micro; then
        summary "micro $(L 'установлен' 'installed')"
        return 0
    fi
    info "$(L 'micro нет в репозиториях — ставлю релиз с GitHub' 'micro is not in repositories — installing the GitHub release')"
    install_micro_binary || return 1
    summary "micro $(L 'установлен' 'installed') (GitHub → /usr/local/bin)"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

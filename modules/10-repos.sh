#!/usr/bin/env bash
# @group   repos
# @title   Репозитории дистрибутива + HTTPS | Distribution repositories + HTTPS
# @default on
# @os      all

# Переводит на https только те хосты, которые реально отвечают по https
switch_to_https() {
    local files=("$@") hosts host
    ((${#files[@]})) || return 0
    hosts=$(grep -hoE 'http://[^/ "$]+' "${files[@]}" 2>/dev/null | sed 's|http://||' | sort -u)
    if [[ -z $hosts ]]; then
        ok "$(L 'Все репозитории уже используют https' 'All repositories already use https')"
        return 0
    fi
    for host in $hosts; do
        if curl -s -o /dev/null --connect-timeout 5 --max-time 15 "https://$host/"; then
            sed -i "s|http://${host//./\\.}|https://$host|g" "${files[@]}"
            ok "https: $host"
        else
            warn "$(L "$host не отвечает по https — оставляю http" "$host does not answer via https — keeping http")"
        fi
    done
}

astra_repos() {
    local list=/etc/apt/sources.list rel="" r
    [[ $OS_VER == 1.7* ]] && rel=1.7
    [[ $OS_VER == 1.8* ]] && rel=1.8
    backup "$list"
    touch "$list"

    # CD/DVD-репозиторий на сервере мешает apt update
    if grep -qE '^\s*deb\s+cdrom:' "$list"; then
        sed -i -E 's/^(\s*deb\s+cdrom:)/# \1/' "$list"
        info "$(L 'Отключён cdrom-репозиторий' 'cdrom repository disabled')"
    fi

    [[ -z $rel ]] && return 0
    grep -qsE '^\s*deb\s+https?://dl\.astralinux\.ru' "$list" /etc/apt/sources.list.d/*.list && return 0
    ask_yn ASTRA_ONLINE_REPOS "$(L "Добавить сетевые репозитории Astra Linux $rel (dl.astralinux.ru)?" \
                                   "Add Astra Linux $rel online repositories (dl.astralinux.ru)?")" y || return 0
    {
        echo ""
        echo "# linux-start: Astra Linux $rel"
        if [[ $rel == 1.7 ]]; then
            for r in main update base extended; do
                echo "deb https://dl.astralinux.ru/astra/stable/1.7_x86-64/repository-$r/ 1.7_x86-64 main contrib non-free"
            done
        else
            echo "deb https://dl.astralinux.ru/astra/stable/1.8_x86-64/main-repository/ 1.8_x86-64 main contrib non-free non-free-firmware"
            echo "deb https://dl.astralinux.ru/astra/stable/1.8_x86-64/extended-repository/ 1.8_x86-64 main contrib non-free non-free-firmware"
        fi
    } >> "$list"
    summary "$(L "Добавлены репозитории Astra $rel" "Astra $rel repositories added")"
}

debian_standard_sources() {
    local cn=$OS_CODENAME comps="main contrib non-free"
    local keyring=/usr/share/keyrings/debian-archive-keyring.gpg signed="" bp=""
    case $cn in
        bookworm|trixie) comps="$comps non-free-firmware" ;;
        *)
            warn "$(L "Debian $OS_VER больше не поддерживается — обновитесь до Debian 12/13" \
                      "Debian $OS_VER is EOL — upgrade to Debian 12/13")"
            return 0 ;;
    esac
    ask_yn DEBIAN_STANDARD_SOURCES "$(L "Заменить список репозиториев на официальные Debian $cn ($comps)?" \
                                        "Replace repositories with official Debian $cn ($comps)?")" y || return 0
    [[ -f $keyring ]] && signed="Signed-By: $keyring"
    ask_yn DEBIAN_BACKPORTS "$(L 'Подключить backports?' 'Enable backports?')" n && bp=" ${cn}-backports"

    backup /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources
    [[ -f /etc/apt/sources.list ]] && mv /etc/apt/sources.list /etc/apt/sources.list.linux-start.bak
    cat > /etc/apt/sources.list.d/debian.sources <<EOF
# linux-start: official Debian repositories
Types: deb
URIs: https://deb.debian.org/debian
Suites: ${cn} ${cn}-updates${bp}
Components: ${comps}
${signed}

Types: deb
URIs: https://security.debian.org/debian-security
Suites: ${cn}-security
Components: ${comps}
${signed}
EOF
    summary "$(L "Репозитории Debian $cn: $comps$bp" "Debian $cn repositories: $comps$bp")"
}

ubuntu_components() {
    local f
    ask_yn UBUNTU_UNIVERSE "$(L 'Включить компоненты universe и multiverse?' 'Enable universe and multiverse components?')" y || return 0
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [[ -f $f ]] && grep -qE '^deb .*ubuntu\.com' "$f" || continue
        backup "$f"
        sed -i -E '/^deb(-src)? .*ubuntu\.com/ { / universe( |$)/! s/$/ universe/; / multiverse( |$)/! s/$/ multiverse/ }' "$f"
    done
    f=/etc/apt/sources.list.d/ubuntu.sources
    if [[ -f $f ]]; then
        backup "$f"
        sed -i -E '/^Components:/ { / universe( |$)/! s/$/ universe/; / multiverse( |$)/! s/$/ multiverse/ }' "$f"
    fi
    summary "$(L 'Ubuntu: universe и multiverse включены' 'Ubuntu: universe and multiverse enabled')"
}

repos_debian() {
    local f files=()
    [[ $OS_ID == astra ]] && astra_repos

    info "$(L 'Обновляю индексы пакетов…' 'Updating package index…')"
    pkg_update || warn "$(L 'apt update завершился с ошибкой' 'apt update failed')"
    pkg_ensure ca-certificates curl gnupg || pkg_ensure ca-certificates curl

    case $OS_ID in
        debian) debian_standard_sources ;;
        ubuntu) ubuntu_components ;;
    esac

    for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f $f ]] && files+=("$f")
    done
    backup "${files[@]}"
    switch_to_https "${files[@]}"

    if ! pkg_update; then
        warn "$(L 'apt update с новыми настройками не прошёл — откатываю https-замену' \
                  'apt update failed with new settings — reverting https switch')"
        restore "${files[@]}"
        pkg_update || return 1
    fi
}

repos_rhel() {
    local f files=() centos_stream=0
    grep -qi stream /etc/centos-release 2>/dev/null && centos_stream=1

    # CentOS 7 / 8 / Stream 8 — EOL, зеркала переехали в vault
    if [[ $OS_ID == centos && ( $OS_MAJOR == 7 || $OS_MAJOR == 8 ) ]]; then
        if ask_yn CENTOS_VAULT "$(L "CentOS $OS_MAJOR больше не поддерживается. Перевести репозитории на архив vault.centos.org?" \
                                    "CentOS $OS_MAJOR is EOL. Switch repositories to the vault.centos.org archive?")" y; then
            backup /etc/yum.repos.d/CentOS-*.repo
            sed -i -e 's|^mirrorlist=|#mirrorlist=|' \
                   -e 's|^#\s*baseurl=http://mirror\.centos\.org|baseurl=https://vault.centos.org|' \
                   -e 's|^baseurl=http://mirror\.centos\.org|baseurl=https://vault.centos.org|' \
                   /etc/yum.repos.d/CentOS-*.repo
            summary "$(L 'CentOS: репозитории переведены на vault.centos.org' 'CentOS: repositories switched to vault.centos.org')"
        fi
        warn "$(L 'Обновлений безопасности для этой версии больше нет — рекомендуется миграция на Rocky/Alma/RHEL' \
                  'No more security updates for this release — migration to Rocky/Alma/RHEL is recommended')"
    fi
    (( centos_stream )) && [[ $OS_MAJOR == 8 ]] && \
        warn "CentOS Stream 8 is EOL"

    for f in /etc/yum.repos.d/*.repo; do [[ -f $f ]] && files+=("$f"); done
    backup "${files[@]}"
    command -v curl >/dev/null || pkg_install curl
    switch_to_https "${files[@]}"

    # EPEL — там ufw, fail2ban и часть утилит
    if [[ $OS_ID != redos ]] && ! pkg_installed epel-release && ! pkg_installed "oracle-epel-release-el$OS_MAJOR"; then
        if ask_yn EPEL "$(L 'Подключить EPEL (нужен для ufw, fail2ban, htop)?' 'Enable EPEL (needed for ufw, fail2ban, htop)?')" y; then
            case $OS_ID in
                rhel)
                    $PKG install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${OS_MAJOR}.noarch.rpm" </dev/null
                    command -v subscription-manager >/dev/null && \
                        subscription-manager repos --enable "codeready-builder-for-rhel-${OS_MAJOR}-$(arch)-rpms"
                    ;;
                ol) pkg_install "oracle-epel-release-el${OS_MAJOR}" ;;
                *)  pkg_install epel-release ;;
            esac
            # CRB / PowerTools — зависимости части пакетов EPEL
            if (( OS_MAJOR >= 9 )); then
                $PKG config-manager --set-enabled crb 2>/dev/null
            elif (( OS_MAJOR == 8 )); then
                $PKG config-manager --set-enabled powertools 2>/dev/null
            fi
            summary "$(L 'EPEL подключён' 'EPEL enabled')"
        fi
    fi

    if ! pkg_update; then
        warn "$(L 'makecache не прошёл — откатываю https-замену' 'makecache failed — reverting https switch')"
        restore "${files[@]}"
        pkg_update || return 1
    fi
}

module_run() {
    if [[ $FAMILY == debian ]]; then repos_debian; else repos_rhel; fi || return 1
    summary "$(L 'Репозитории настроены' 'Repositories configured') ($PKG)"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

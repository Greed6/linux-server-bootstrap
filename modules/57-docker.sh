#!/usr/bin/env bash
# @group   software
# @title   Docker + Docker Compose | Docker + Docker Compose
# @default off
# @os      all
# Номер 57: выполняется после ufw (50), чтобы сразу настроить связку Docker + ufw

DOCKER_PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

# Официальный репозиторий download.docker.com
docker_repo_debian() {
    local codename
    codename=$(. /etc/os-release; echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
    [[ -n $codename ]] || { err "$(L 'Не удалось определить кодовое имя дистрибутива' 'Cannot detect distribution codename')"; return 1; }

    # Пакеты из дистрибутива конфликтуют с docker-ce
    local p old=()
    for p in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        pkg_installed "$p" && old+=("$p")
    done
    if ((${#old[@]})); then
        info "$(L 'Удаляю конфликтующие пакеты' 'Removing conflicting packages'): ${old[*]}"
        apt-get remove -y -q "${old[@]}" </dev/null
    fi

    pkg_ensure ca-certificates curl || return 1
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$OS_ID/gpg" -o /etc/apt/keyrings/docker.asc || return 1
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$OS_ID $codename stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -q </dev/null
}

docker_repo_rhel() {
    local url=https://download.docker.com/linux/centos/docker-ce.repo
    [[ $OS_ID == rhel ]] && url=https://download.docker.com/linux/rhel/docker-ce.repo
    command -v curl >/dev/null || pkg_install curl
    curl -fsSL "$url" -o /etc/yum.repos.d/docker-ce.repo || return 1
    $PKG makecache -q </dev/null
}

docker_install() {
    case $OS_ID in
        ubuntu|debian)
            docker_repo_debian || return 1
            pkg_install "${DOCKER_PKGS[@]}"
            ;;
        rhel|centos|rocky|almalinux|ol)
            docker_repo_rhel || return 1
            # --allowerasing заменяет podman/runc, которые конфликтуют с containerd.io
            $PKG install -y -q --allowerasing "${DOCKER_PKGS[@]}" </dev/null
            ;;
    esac
}

# Ротация логов контейнеров: без неё json-логи растут бесконечно
docker_daemon_json() {
    local f=/etc/docker/daemon.json tmp
    ask_yn DOCKER_LOG_ROTATION "$(L 'Включить ротацию логов контейнеров (10 МБ × 3 файла)?' \
                                    'Enable container log rotation (10 MB × 3 files)?')" y || return 0
    mkdir -p /etc/docker
    backup "$f"
    if [[ -s $f ]]; then
        if command -v jq >/dev/null; then
            tmp=$(mktemp)
            jq '. + {"log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "3"}}' "$f" > "$tmp" \
                && cat "$tmp" > "$f"
            rm -f "$tmp"
        else
            warn "$(L "$f уже есть, а jq не установлен — не меняю" "$f exists and jq is missing — leaving it as is")"
            return 0
        fi
    else
        cat > "$f" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    fi
    summary "Docker: $(L 'ротация логов' 'log rotation') 10m × 3"
}

# Docker публикует порты через iptables в обход ufw. Цепочка DOCKER-USER
# проверяется раньше правил Docker: пропускаем ответы и локальные сети,
# разрешаем то, что открыто через «ufw route allow», остальное — DROP.
docker_ufw() {
    local f=/etc/ufw/after.rules
    [[ $(detect_fw) == ufw ]] || return 0
    ask_yn DOCKER_UFW "$(L 'Закрыть опубликованные порты контейнеров файрволом ufw (открывать через «ufw route allow»)?' \
                          'Protect published container ports with ufw (open them via "ufw route allow")?')" y || return 0
    backup "$f"
    sed -i '/^# >>> linux-start docker/,/^# <<< linux-start docker/d' "$f"
    cat >> "$f" <<'EOF'
# >>> linux-start docker
*filter
:ufw-user-forward - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -s 10.0.0.0/8 -j RETURN
-A DOCKER-USER -s 172.16.0.0/12 -j RETURN
-A DOCKER-USER -s 192.168.0.0/16 -j RETURN
-A DOCKER-USER -m conntrack --ctstate NEW -j DROP
-A DOCKER-USER -j RETURN
COMMIT
# <<< linux-start docker
EOF
    ufw reload >/dev/null || { err "ufw reload failed"; restore "$f"; ufw reload >/dev/null; return 1; }
    summary "Docker + ufw: $(L 'порты контейнеров закрыты извне' 'container ports closed from outside')"
    info "$(L 'Открыть порт контейнера (порт внутри контейнера):' 'Open a container port (the port inside the container):') ufw route allow proto tcp from any to any port 80"
}

docker_group_user() {
    local user
    user=$(cat "$LS_STATE_DIR/ssh_user" 2>/dev/null)
    user=${user:-${SUDO_USER:-}}
    [[ -z $user || $user == root ]] && ! answer_get DOCKER_USER >/dev/null && return 0
    ask user DOCKER_USER "$(L 'Пользователь для группы docker («-» — никого)' 'User for the docker group ("-" — none)')" "$user"
    [[ -z $user || $user == - || $user == root ]] && return 0
    id -u "$user" >/dev/null 2>&1 || { warn "$(L "Пользователя $user нет" "User $user does not exist")"; return 0; }
    usermod -aG docker "$user"
    summary "$(L "$user добавлен в группу docker" "$user added to the docker group")"
    warn "$(L 'Группа docker даёт права, равные root. Изменение вступит в силу после повторного входа.' \
              'The docker group is root-equivalent. Takes effect after re-login.')"
}

module_run() {
    if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
        ok "$(L 'Docker и compose уже установлены' 'Docker and compose are already installed')"
    else
        docker_install || { err "$(L 'Не удалось установить Docker' 'Failed to install Docker')"; return 1; }
    fi
    command -v docker >/dev/null || return 1

    docker_daemon_json
    svc_enable_now docker || return 1
    # containerd.io на части систем не включается сам
    has_systemd && systemctl enable containerd >/dev/null 2>&1

    docker_group_user
    docker_ufw

    summary "$(docker --version 2>/dev/null)"
    summary "$(docker compose version 2>/dev/null || docker-compose --version 2>/dev/null)"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }

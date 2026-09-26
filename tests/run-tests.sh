#!/usr/bin/env bash
#
# Интеграционные тесты в Docker (контейнеры с systemd).
# Integration tests in Docker (systemd containers).
#
#   tests/run-tests.sh                 # все цели / all targets
#   tests/run-tests.sh debian12 rocky9 # выбранные / selected
#   LS_TEST_MODULES="ufw crowdsec" tests/run-tests.sh debian12
#   KEEP=1 tests/run-tests.sh debian12 # не удалять контейнер / keep container
#
# Контейнерам нужен --privileged (systemd, iptables для ufw).
# Ограничения контейнера: swap, auditd, hostname, sysctl ядра — не тестируются.

set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/tests/out"
mkdir -p "$OUT"

target_spec() {
    case $1 in
        debian12)   echo "debian.Dockerfile debian:12" ;;
        debian13)   echo "debian.Dockerfile debian:13" ;;
        ubuntu2204) echo "debian.Dockerfile ubuntu:22.04" ;;
        ubuntu2404) echo "debian.Dockerfile ubuntu:24.04" ;;
        rocky9)     echo "rhel.Dockerfile rockylinux:9" ;;
        alma8)      echo "rhel.Dockerfile almalinux:8" ;;
        alma9)      echo "rhel.Dockerfile almalinux:9" ;;
        ol9)        echo "rhel.Dockerfile oraclelinux:9" ;;
    esac
}
ORDER=(debian12 debian13 ubuntu2204 ubuntu2404 rocky9 alma8 alma9 ol9)
(($#)) && ORDER=("$@")

# Тестовый ключ (приватная часть не нужна)
KEYFILE="$OUT/test_ed25519"
[[ -f $KEYFILE ]] || ssh-keygen -q -t ed25519 -N "" -C "linux-start-test" -f "$KEYFILE"
PUBKEY=$(cat "$KEYFILE.pub")

results=()
for t in "${ORDER[@]}"; do
    spec=$(target_spec "$t")
    [[ -z $spec ]] && { echo "Unknown target: $t"; continue; }
    dockerfile=${spec%% *}; base=${spec#* }
    image="linux-start-test:$t"; name="ls-test-$t"
    log="$OUT/$t.log"

    echo "=== $t ($base) ==="
    if ! docker build -q -t "$image" --build-arg "BASE=$base" -f "$ROOT/tests/docker/$dockerfile" "$ROOT/tests/docker" >"$log" 2>&1; then
        echo "  build failed, see $log"; results+=("$t: BUILD FAILED"); continue
    fi
    docker rm -f -v "$name" >/dev/null 2>&1
    docker run -d --name "$name" --privileged --cgroupns=host \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock \
        -v "$ROOT:/opt/linux-start:ro" -v /var/lib/docker -v /var/lib/containerd "$image" >/dev/null || { results+=("$t: RUN FAILED"); continue; }

    # Ждём, пока systemd поднимется
    for _ in $(seq 1 30); do
        state=$(docker exec "$name" systemctl is-system-running 2>/dev/null)
        [[ $state == running || $state == degraded ]] && break
        sleep 1
    done

    start=$(date +%s)
    docker exec -e LS_SSH_KEYS="$PUBKEY" -e LS_TEST_MODULES="${LS_TEST_MODULES:-}" -e TERM=dumb "$name" \
        bash /opt/linux-start/linux-start.sh -y -c /opt/linux-start/tests/ci-answers.conf >>"$log" 2>&1
    rc=$?
    dur=$(( $(date +%s) - start ))

    echo "--- verify ---" >>"$log"
    docker exec -e LS_TEST_MODULES="${LS_TEST_MODULES:-}" "$name" bash /opt/linux-start/tests/verify.sh | tee -a "$log"
    vrc=${PIPESTATUS[0]}

    if (( rc == 0 && vrc == 0 )); then res="PASS"; else res="FAIL (script rc=$rc, verify rc=$vrc)"; fi
    results+=("$t: $res [${dur}s]")
    [[ ${KEEP:-0} == 1 ]] || docker rm -f -v "$name" >/dev/null
done

echo
echo "===== SUMMARY ====="
printf '  %s\n' "${results[@]}"
printf '%s\n' "${results[@]}" | grep -qv ': PASS' && exit 1
exit 0

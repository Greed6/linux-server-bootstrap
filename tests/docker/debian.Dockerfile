# Тестовый образ Debian/Ubuntu с systemd / test image with systemd
ARG BASE=debian:12
FROM ${BASE}
ENV container=docker DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends systemd systemd-sysv iproute2 procps \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && (systemctl mask systemd-logind getty.target console-getty.service 2>/dev/null || true)
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]

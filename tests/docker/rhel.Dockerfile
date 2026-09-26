# Тестовый образ RHEL-семейства с systemd / test image with systemd
ARG BASE=rockylinux:9
FROM ${BASE}
ENV container=docker
RUN (command -v dnf >/dev/null && dnf install -y systemd procps-ng iproute || true) \
    && (command -v dnf >/dev/null && dnf clean all || true)
STOPSIGNAL SIGRTMIN+3
CMD ["/usr/sbin/init"]

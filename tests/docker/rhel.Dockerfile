# Тестовый образ RHEL-семейства с systemd / test image with systemd
ARG BASE=rockylinux:9
FROM ${BASE}
ENV container=docker
# У EOL-образов (CentOS 8, Stream 8) зеркала мертвы — установка может не пройти,
# systemd в этих образах уже есть; зеркала чинит сам скрипт (модуль repos)
RUN (dnf install -y systemd procps-ng iproute || true) && (dnf clean all || true)
STOPSIGNAL SIGRTMIN+3
CMD ["/usr/sbin/init"]

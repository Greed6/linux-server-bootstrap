# linux-start

Модульный скрипт первичной настройки Linux-сервера с меню-чеклистом на русском или английском.
*Modular initial Linux server setup script with a checklist menu in Russian or English — [English below](#english).*

**Поддерживаемые ОС:** Ubuntu 22.04 / 24.04, Debian 12 / 13, RHEL / Rocky / AlmaLinux / Oracle Linux 8–9, CentOS 8 / Stream 8 / 9 / 10.

CentOS 8 и Stream 8 больше не получают обновлений: скрипт переводит их на архив `vault.centos.org` и предупреждает о необходимости миграции. CentOS 7 / RHEL 7 не поддерживаются — скрипт завершится с сообщением.

## Быстрый старт

### Одной командой

```bash
curl -fsSL https://raw.githubusercontent.com/Greed6/linux-server-bootstrap/main/install.sh | sudo bash
```

Если `curl` нет (минимальный Debian):

```bash
wget -qO- https://raw.githubusercontent.com/Greed6/linux-server-bootstrap/main/install.sh | sudo bash
```

[`install.sh`](install.sh) скачивает скрипт в `/opt/linux-server-bootstrap` и сразу открывает меню. Повторный запуск той же команды обновляет скрипт до последней версии (каталог заменяется целиком — не храните в нём свои файлы, например файл ответов).

Аргументы для `linux-start.sh` передаются после `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/Greed6/linux-server-bootstrap/main/install.sh | sudo bash -s -- --lang en --text-menu
curl -fsSL https://raw.githubusercontent.com/Greed6/linux-server-bootstrap/main/install.sh | sudo bash -s -- -m "timezone ntp ufw" -y
```

**Приватный репозиторий.** Пока репозиторий приватный, GitHub отдаёт файлы только с токеном. Создайте [fine-grained token](https://github.com/settings/personal-access-tokens/new) с доступом *Contents: Read-only* к этому репозиторию и передайте его обоим запросам:

```bash
export GITHUB_TOKEN=github_pat_...
curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://raw.githubusercontent.com/Greed6/linux-server-bootstrap/main/install.sh | sudo GITHUB_TOKEN="$GITHUB_TOKEN" bash
```

Переменные `install.sh`: `GITHUB_TOKEN`, `LS_REF` (ветка или тег, по умолчанию `main`), `LS_DEST` (каталог установки).

> Перед запуском через `curl | bash` можно посмотреть, что именно будет выполнено: `curl -fsSL <url>/install.sh | less`.

### Через git

```bash
git clone git@github.com:Greed6/linux-server-bootstrap.git
cd linux-server-bootstrap
sudo ./linux-start.sh
```

1. При первом запуске скрипт спрашивает, ставить ли русскую локализацию по умолчанию. Если да — добавляется `ru_RU.UTF-8`, и меню будет на русском; если нет — на английском. Ответ запоминается.
2. Открывается меню с галочками, сгруппированное по разделам. Пробел — отметить, Enter — установить. Если `whiptail` нет, показывается текстовое меню (номера `1 3 5-7`, `a` — все, Enter — установить).
3. Выбранные модули выполняются по порядку, в конце — итоговый отчёт.

После установки скрипт предлагает вернуться в меню и доустановить компоненты. Запустить его снова можно в любой момент командой:

```bash
sudo linux-start
```

Команда создаётся при первом запуске (`/usr/local/sbin/linux-start`). Если репозиторий был в `/tmp`, он копируется в `/opt/linux-server-bootstrap`. При повторном запуске меню открывается без отметок, а уже выполненные модули помечены `✓` — отмечайте только то, что нужно доустановить.

## Модули

| Группа | Модуль | По умолч. | Что делает |
|---|---|---|---|
| Репозитории | `repos` | ✔ | Официальные репозитории дистрибутива, перевод на HTTPS (только если хост отвечает по https; зеркала из metalink/mirrorlist — только https), universe/multiverse, EPEL+CRB, CentOS → vault. Откат при ошибке `apt update`/`makecache` |
| | `upgrade` | ✔ | Обновление пакетов |
| | `auto-updates` | ✔ | `unattended-upgrades` / `dnf-automatic`, только обновления безопасности |
| Система | `locale` | | Добавить/сменить системную локаль |
| | `hostname` | ✔ | Имя сервера, `/etc/hosts`, `preserve_hostname` для cloud-init |
| | `timezone` | ✔ | Часовой пояс, по умолчанию Europe/Moscow (UTC+3) |
| | `ntp` | ✔ | chrony с указанными NTP-серверами (по умолчанию `ru.pool.ntp.org`), отключение timesyncd/ntpd |
| | `swap` | ✔ | Swap-файл нужного размера (если swap нет) и `vm.swappiness` |
| | `sysctl` | ✔ | syncookies, rp_filter, запрет redirects/source routing, kptr/dmesg restrict |
| | `journald` | ✔ | Постоянный журнал, лимит размера и срока хранения |
| Программы | `base-tools` | ✔ | curl, wget, htop, git, rsync, tmux, bash-completion, jq, dnsutils… |
| | `nano`, `mc`, `micro` | ✔ | Редакторы; micro — из репозитория или с GitHub |
| | `docker` | | Docker CE + Compose + Buildx из официального репозитория, ротация логов, пользователь в группе docker, связка с ufw (см. ниже) |
| SSH | `ssh-keys` | ✔ | openssh-server, пользователь с sudo, ключ (вставить / URL / файл) |
| | `ssh-port` | | Нестандартный порт (с сохранением 22 до проверки), SELinux, файрвол, fail2ban |
| | `ssh-hardening` | ✔ | Только ключи, запрет root, MaxAuthTries. **Не включится, если ни у кого нет ключа** |
| Безопасность | `ufw` | ✔ | deny incoming, IPv4+IPv6, открыт только SSH. На RHEL без ufw — firewalld |
| | `fail2ban` | ✔ | jail sshd, бан 1 ч с нарастанием до недели, доверенные IP |
| | `crowdsec` | | CrowdSec + firewall bouncer, выбор порта LAPI; при открытии для других серверов порт добавляется в файрвол |
| | `crowdsec-console` | | Подключение к app.crowdsec.net |
| | `auditd` | | Аудит изменений учёток, sudoers, sshd, cron |
| | `selinux-apparmor` | ✔ | Только отчёт о статусе |
| Уведомления | `telegram-ssh` | | Сообщение в Telegram при каждом входе по SSH (pam_exec) |

`fail2ban` и `crowdsec` помечены как конфликтующие — при выборе обоих скрипт предупредит.

## Параметры запуска

```bash
sudo ./linux-start.sh                          # меню
sudo ./linux-start.sh --list                   # список модулей
sudo ./linux-start.sh -m "timezone ntp ufw"    # без меню, выбранные модули
sudo ./linux-start.sh -c answers.conf          # ответы из файла
sudo ./linux-start.sh -c answers.conf -y       # полностью без вопросов
sudo ./linux-start.sh --lang en --text-menu
sudo bash modules/22-timezone.sh               # один модуль отдельно
```

Файл ответов: скопируйте [`answers.example.conf`](answers.example.conf). Каждому вопросу соответствует переменная `LS_<КЛЮЧ>`; если она задана, вопрос не задаётся.

## Безопасность запуска

- Изменяемые файлы копируются в `/var/backups/linux-start/<дата>/`, журнал — `/var/log/linux-start.log`.
- Конфигурация sshd проверяется `sshd -t` и при ошибке откатывается.
- **После изменения SSH не закрывайте текущую сессию** — проверьте вход в новом окне.
- Docker публикует порты в обход ufw. Модуль `docker` (если ufw активен) добавляет правила в цепочку `DOCKER-USER`: опубликованные порты контейнеров закрыты извне, пока вы не откроете их командой `ufw route allow proto tcp from any to any port <порт внутри контейнера>`. Доступ из локальных сетей (10/8, 172.16/12, 192.168/16) остаётся.

## Как добавить свой модуль

Создайте `modules/NN-<id>.sh` — он сам появится в меню:

```bash
#!/usr/bin/env bash
# @group     software                      # id группы из lib/groups.conf
# @title     Docker | Docker                # название RU | EN
# @default   off                            # отмечен ли по умолчанию
# @os        debian,rhel,!centos            # где доступен (all по умолчанию)
# @conflicts podman                         # несовместимые модули (необязательно)

module_run() {
    local ver
    ask ver DOCKER_VERSION "$(L 'Версия' 'Version')" "latest"     # LS_DOCKER_VERSION в файле ответов
    ask_yn DOCKER_COMPOSE "$(L 'Ставить compose?' 'Install compose?')" y && ...
    pkg_install docker-ce || return 1
    summary "Docker $(L 'установлен' 'installed')"
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && { . "$(dirname "$(readlink -f "$0")")/../lib/common.sh"; ls_standalone; }
```

`NN` задаёт порядок выполнения. Новая группа — строка в [`lib/groups.conf`](lib/groups.conf). Функции для модулей (`ask`, `ask_yn`, `pkg_install`, `fw_allow`, `sshd_write_block`, `backup`…) — в [`lib/common.sh`](lib/common.sh).

## Тесты

Интеграционные тесты запускают скрипт в Docker-контейнерах с systemd и проверяют результат ([`tests/verify.sh`](tests/verify.sh)):

```bash
tests/run-tests.sh                               # все дистрибутивы
tests/run-tests.sh debian12 rocky9
LS_TEST_MODULES="ufw crowdsec" tests/run-tests.sh debian12
```

Проверяются Debian 12/13, Ubuntu 22.04/24.04, Rocky 9, AlmaLinux 8/9, Oracle Linux 9, CentOS 8, CentOS Stream 8/9/10. В контейнере не проверяются swap, auditd и hostname.

---

## English

`linux-start` is a modular first-boot setup script for Linux servers. On the first run it asks whether to install the Russian locale as default; the checklist menu is then shown in Russian or English. Every task is a separate script in `modules/` with metadata in header comments, so the menu is built automatically — drop in a new `NN-id.sh` to add an item, delete the file to remove it.

```bash
curl -fsSL https://raw.githubusercontent.com/Greed6/linux-server-bootstrap/main/install.sh | sudo bash
# private repository: add -H "Authorization: Bearer $GITHUB_TOKEN" to curl and sudo GITHUB_TOKEN=... bash

sudo ./linux-start.sh              # checklist menu
sudo linux-start                   # re-run later to install more
sudo ./linux-start.sh --list       # list modules
sudo ./linux-start.sh -c answers.conf -y   # unattended
```

See the module table above; titles are shown in English when English is selected. Backups go to `/var/backups/linux-start/`, the log to `/var/log/linux-start.log`.

## License

[MIT](LICENSE)

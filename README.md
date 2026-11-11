# Ubuntu Server Setup 2026 — Ansible Playbook

Универсальный плейбук для первичной настройки Ubuntu Server 22.04+: пользователь с sudo, SSH-ключ, безопасность (UFW, fail2ban, AppArmor, auditd), логи, оптимизация ядра. Опционально — мониторинг и бэкапы.

Все команды ниже используют **плейсхолдеры** — подставляйте свои значения:

| Плейсхолдер | Что подставить |
|---|---|
| `<SERVER>` | Имя хоста в `inventory.yaml` (станет hostname сервера), напр. `web01` |
| `<SERVER_IP>` | Публичный IP сервера, напр. `1.2.3.4` |
| `<SSH_USER>` | Пользователь для входа на Этапе 1 (обычно `root`) |
| `<VAULT_PASSWORD>` | Ваш пароль для шифрования секретов |
| `<RESTIC_PASSWORD>` | Пароль для restic-репозитория (генерируется) |

---

## ⚠️ Меры предосторожности

Перед работой с боевым сервером убедитесь, что:

1. У вас есть SSH-доступ к серверу (по паролю на Этапе 1 — этого достаточно).
2. Есть резервный доступ (консоль хостинга, IPMI, KVM) — на случай блокировки SSH.
3. Вы знаете пароль `root` (или пользователя из `<SSH_USER>`).

> Этап 2 (`activate`) **перезапускает SSH и включает фаервол**. Не запускайте его, пока не убедились, что вход под `bestadmin` по ключу работает.

---

## 1. Подготовка репозитория к новому серверу

### 1.1 Установка Ansible (на управляющей машине)

```bash
# macOS
brew install ansible

# Ubuntu/Debian
sudo apt update && sudo apt install -y ansible
```

### 1.2 Что где настраивается

| Файл/папка | Что здесь указывается |
|---|---|
| `inventory.yaml` | Серверы: имя, IP, пользователь, порт |
| `group_vars/all/vars.yml` | Общая конфигурация для всех серверов (пакеты, SSH, фаервол, логи, ядро) |
| `host_vars/<SERVER>/vars.yml` | Переопределение конфигурации для конкретного сервера (опционально) |
| `group_vars/all/vault.yml` | Зашифрованные секреты, общие для всех серверов |
| `host_vars/<SERVER>/vault.yml` | Зашифрованные секреты конкретного сервера (напр. `ansible_password`) |

### 1.3 inventory.yaml — что указать

Добавьте сервер в группу (например `production`):

```yaml
all:
  children:
    production:
      hosts:
        <SERVER>:                    # ← имя, станет hostname
          ansible_host: <SERVER_IP>  # ← IP сервера
          ansible_user: <SSH_USER>   # ← Этап 1: root; после prepare: bestadmin
          ansible_port: 22
```

> **ВАЖНО.** Пароль в `inventory.yaml` не пишите. На Этапе 1 пароль вводится вручную (`--ask-pass`) либо лежит зашифрованным в `host_vars/<SERVER>/vault.yml` как `ansible_password`.

### 1.4 group_vars/all/vars.yml — основные переменные

Ключевые места, которые чаще всего меняются:

```yaml
admin_ssh_public_key_file: "~/.ssh/id_ed25519.pub"   # ваш публичный SSH-ключ

common:
  users:
    - name: "bestadmin"               # пользователь с sudo, создаётся на Этапе 1
      ssh_key: "{{ lookup('file', admin_ssh_public_key_file) }}"
      groups: ["sudo"]
      shell: "/bin/bash"

security:
  ssh:
    port: 22
    disable_root: false               # Этап 1: root оставляем; активация решит
    password_auth: true
  firewall:
    rules:
      - port: "22"                    # SSH
        proto: "tcp"
        comment: "SSH доступ"
      - port: "80"
        proto: "tcp"
        comment: "HTTP"
      - port: "443"
        proto: "tcp"
        comment: "HTTPS"

backup:
  restic:
    password: "{{ vault_restic_password }}"   # пароль restic берётся из vault
```

### 1.5 Секреты: что создавать и шифровать

**Когда vault не нужен.** Для этапов `prepare` и `activate` секретов в vault не требуется:
пароль на Этапе 1 вводится интерактивно (`--ask-pass`), а с Этапа 2 вход идёт по SSH-ключу.

**Когда vault обязателен.** Для `playbook_backup.yaml` нужна переменная `vault_restic_password`
(на неё ссылается `group_vars/all/vars.yml`). Без неё запуск бэкапов упадёт.

Создание секрета:

```bash
# 1. Общий для всех серверов
mkdir -p group_vars/all
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# 2. Заполните значения, затем зашифруйте
ansible-vault encrypt group_vars/all/vault.yml
# введите <VAULT_PASSWORD>
```

Секрет, уникальный для одного сервера (например, пароль root для первого входа):

```bash
mkdir -p host_vars/<SERVER>
ansible-vault create host_vars/<SERVER>/vault.yml
```

Внутри файла:

```yaml
ansible_password: "<ROOT_PASSWORD>"   # пароль только этого сервера
```

Редактирование: `ansible-vault edit host_vars/<SERVER>/vault.yml`
Просмотр: `ansible-vault view host_vars/<SERVER>/vault.yml`

---

## 2. Плейбуки и их состав

### 2.1 Плейбуки

| Плейбук | Роли | Что делает | Когда запускать |
|---|---|---|---|
| `playbook_prepare.yaml` | `common`, `security`, `logging`, `kernel` | **Этап 1.** Пользователь `bestadmin` + SSH-ключ, пакеты и обновления, SSH-конфиг (без перезапуска), правила UFW (без включения), логи, ядро. Безопасен — root и фаервол не трогаются | Первый запуск на новом сервере, под `root` |
| `playbook_activate.yaml` | `security_activate` | **Этап 2.** Перезапуск SSH, включение UFW, fail2ban, AppArmor, auditd, sysctl hardening | После успешного prepare и проверки SSH, под `bestadmin` |
| `playbook_monitoring.yaml` | `monitoring` | node_exporter, health-check, smartmontools | Опционально, после activate |
| `playbook_backup.yaml` | `backup`, `backup_activate` | restic, репозиторий, шифрование, systemd-таймеры | Опционально, после activate (требует vault) |
| `playbook.yaml` | `common`, `security`, `logging`, `kernel` | То же, что prepare, но с предупреждением и перезагрузкой в конце | Не рекомендуется — используйте prepare/activate |

### 2.2 Роли (функции)

| Роль | Функции | Теги для запуска по отдельности |
|---|---|---|
| `common` | пользователь + SSH-ключ, пакеты, обновления, locale, часовой пояс, hostname, sudo, motd, bash/vim, chrony, очистка | `users`, `ssh`, `packages`, `update`, `upgrade`, `hostname`, `timezone`, `locale`, `chrony`, `sudo`, `motd`, `cleanup` |
| `security` | SSH-конфиг (без перезапуска), UFW-правила (без включения), fail2ban-конфиг, AppArmor-профили, auditd-правила, sysctl | `ssh`, `ufw`, `fail2ban`, `apparmor`, `audit`, `sysctl`, `security`, `security_prepare` |
| `security_activate` | перезапуск SSH, включение UFW/fail2ban/AppArmor/auditd, sysctl hardening | `ssh`, `ufw`, `fail2ban`, `apparmor`, `auditd`, `sysctl`, `check` |
| `logging` | logrotate, journald, rsyslog, очистка логов | `logrotate`, `journald`, `rsyslog`, `cleanup`, `logging`, `check` |
| `kernel` | sysctl-параметры, ulimits, swap, io-планировщики | `sysctl`, `kernel`, `check`, `verify` |
| `monitoring` | node_exporter, netdata, health-check, smartmontools | `node_exporter`, `netdata`, `health_checks`, `disk`, `monitoring`, `check` |
| `backup` | restic, репозиторий, шифрование, скрипты | `restic`, `repository`, `encryption`, `age`, `storage`, `backup`, `check` |
| `backup_activate` | systemd-таймеры, cron, скрипты бэкапа | `timers`, `cron`, `scripts`, `repository`, `password`, `check` |

---

## 3. Действия

### 3.0 Проверка состояния сервера без изменений (dry-run)

Любой плейбук можно прогнать в **безопасном режиме проверки**: ничего не меняется,
Ansible лишь показывает, **отличается ли текущее состояние сервера от того, что
описывает плейбук**, и что именно он хотел бы изменить.

- `--check` — симуляция: Ansible «прикидывает», что сделает, но не вносит изменений.
- `--diff` — показывает конкретные отличия (изменённые строки/файлы на сервере).

```bash
ansible-playbook <PLAYBOOK>.yaml -l <SERVER> --check --diff
```

Если для этапа нужен пароль, добавляйте его флаг:

```bash
ansible-playbook playbook_prepare.yaml -l <SERVER> --check --diff --ask-pass     # по паролю
ansible-playbook playbook_backup.yaml -l <SERVER> --check --diff --ask-vault-pass
```

Повторный запуск реальной команды, при котором ничего не изменилось, означает, что
сервер уже соответствует плейбуку (идемпотентность). Так удобно проверять расхождение
состояния сервера и конфигурации.

### 3.1 Этап 1 — prepare (первый запуск сервера)

Под **root**, пароль вводится интерактивно (нигде не хранится):

```bash
ansible-playbook playbook_prepare.yaml -l <SERVER> --ask-pass
```

> `--ask-pass` = Ansible спросит SSH-пароль `<SSH_USER>` в консоли. Секреты создавать не нужно.

Безопасная проверка (ничего не меняет):

```bash
ansible-playbook playbook_prepare.yaml -l <SERVER> --check --diff --ask-pass
```

Если пароль лежит в vault (`host_vars/<SERVER>/vault.yml`), вместо `--ask-pass`:

```bash
ansible-playbook playbook_prepare.yaml -l <SERVER> --ask-vault-pass
```

**Что произойдёт:** создастся пользователь `bestadmin`, скопируется ваш SSH-ключ из
`~/.ssh/id_ed25519.pub`, установятся пакеты, подготовятся SSH/UFW (без применения).

### 3.2 Проверка SSH после prepare (обязательно!)

```bash
ssh -i ~/.ssh/id_ed25519 bestadmin@<SERVER_IP>
sudo ls /
```

Если вход не работает — **не переходите к активации**. Исправьте и повторите prepare.

### 3.3 Переключить inventory на bestadmin (обязательно!)

В `inventory.yaml` замените пользователя у сервера:

```yaml
<SERVER>:
  ansible_host: <SERVER_IP>
  ansible_user: bestadmin     # ← было root
  ansible_port: 22
```

### 3.4 Этап 2 — activate (включение безопасности)

Под `bestadmin`, вход по SSH-ключу — **никаких флагов пароля не нужно**.

**Обязательно сначала безопасная проверка** (ничего не меняет, покажет, что будет
применено):

```bash
ansible-playbook playbook_activate.yaml -l <SERVER> --check --diff
```

Изучите вывод — какие изменения планируются. Затем реальный запуск:

```bash
ansible-playbook playbook_activate.yaml -l <SERVER>
```

**Что произойдёт:** перезапуск SSH, включение UFW, fail2ban, AppArmor, auditd.
root будет заблокирован в SSH.

> Если здесь появляется `[ERROR]: Attempting to decrypt but no vault secrets found.` — см. раздел 4.

Проверка после активации:

```bash
ssh -i ~/.ssh/id_ed25519 bestadmin@<SERVER_IP>
sudo ufw status verbose
sudo fail2ban-client status
sudo apparmor_status
```

### 3.5 Этап 3 — мониторинг (опционально)

```bash
ansible-playbook playbook_monitoring.yaml -l <SERVER> --check --diff
ansible-playbook playbook_monitoring.yaml -l <SERVER>
```

Проверка: `curl http://localhost:9100/metrics`

### 3.6 Этап 4 — бэкапы (опционально, требует vault)

```bash
# если group_vars/all/vault.yml ещё не создан — сделайте по разделу 1.5
ansible-playbook playbook_backup.yaml -l <SERVER> --check --diff --ask-vault-pass
ansible-playbook playbook_backup.yaml -l <SERVER> --ask-vault-pass
```

Проверка: `sudo systemctl status restic-backup.timer` и `sudo restic snapshots --repo /backup/repository --password-file /etc/backup/restic-password`

### 3.7 Запуск отдельных функций (ролей/тегов)

`--tags` запускает только указанную функцию (список — в разделе 2.2):

```bash
# Только пользователи и SSH-ключи
ansible-playbook playbook_prepare.yaml -l <SERVER> --tags "users" --ask-pass

# Только sysctl-настройки ядра
ansible-playbook playbook_prepare.yaml -l <SERVER> --tags "sysctl" --ask-pass

# Только логи
ansible-playbook playbook_prepare.yaml -l <SERVER> --tags "logging" --ask-pass

# Активация только фаервола
ansible-playbook playbook_activate.yaml -l <SERVER> --tags "ufw"

# Активация только fail2ban
ansible-playbook playbook_activate.yaml -l <SERVER> --tags "fail2ban"
```

---

## 4. Troubleshooting

### 4.1 `[ERROR]: Attempting to decrypt but no vault secrets found.`

**Причина:** в `host_vars/<SERVER>/vault.yml` (или `group_vars/all/vault.yml`) лежит
зашифрованный секрет (например `ansible_password`), а запуск сделан без пароля от vault.

**Решение (варианты):**
- Запустите с паролем vault: добавьте `--ask-vault-pass`.
- Либо удалите ненужный vault-файл и используйте вход по ключу/`--ask-pass`:

```bash
rm -rf host_vars/<SERVER>/vault.yml
```

### 4.2 `Connection to <IP> closed.` после prepare

**Причины:**
- Вход идёт как `root`, но SSH-конфиг уже изменён. Переключите `ansible_user: bestadmin`
  (prepare создал этого пользователя с ключом) и попробуйте снова.
- Виноват ControlMaster из `ansible.cfg` — старые соединения «залипли»:

```bash
# убить кэшированные SSH-соединения Ansible
rm -f /tmp/ansible-ssh-*
```

- Если не помогает — проверьте конфиг SSH на сервере через консоль хостинга:

```bash
sudo sshd -t
sudo systemctl restart ssh
```

### 4.3 `ansible-playbook` просит vault password

```bash
# Если файл ещё не зашифрован:
ansible-vault encrypt group_vars/all/vault.yml

# Или используйте файл с паролем:
echo "<VAULT_PASSWORD>" > .vault_pass
chmod 600 .vault_pass
ansible-playbook playbook_backup.yaml --vault-password-file .vault_pass
```

### 4.4 SSH-доступ потерян после активации

Через консоль хостинга:

```bash
sudo ufw allow 22/tcp
sudo ufw disable   # временно
sudo fail2ban-client set sshd unbanip <ВАШ_IP>
sudo systemctl restart ssh
```

### 4.5 Не найден публичный ключ `~/.ssh/id_ed25519.pub`

```bash
# Сгенерируйте ключ, если его нет:
ssh-keygen -t ed25519 -C "ваш@email.com"

# Или укажите другой путь в group_vars/all/vars.yml:
# admin_ssh_public_key_file: "~/.ssh/id_rsa.pub"
```

---

## 5. Структура проекта

```
ubuntu-server-setup-2026/
├── ansible.cfg             # конфигурация Ansible (SSH, become, paths)
├── inventory.yaml          # серверы: имя, IP, пользователь
├── playbook_prepare.yaml   # Этап 1: подготовка (безопасно)
├── playbook_activate.yaml  # Этап 2: активация безопасности
├── playbook_monitoring.yaml# опционально: мониторинг
├── playbook_backup.yaml    # опционально: бэкапы
├── playbook.yaml           # полный плейбук (не рекомендуется)
├── group_vars/
│   └── all/
│       ├── vars.yml            # общая конфигурация
│       └── vault.yml.example   # шаблон секретов (скопировать → заполнить → зашифровать)
├── host_vars/
│   └── <SERVER>/
│       └── vault.yml           # секреты конкретного сервера (опционально)
└── roles/
    ├── common/             # пользователь, пакеты, обновления, hostname
    ├── security/           # подготовка безопасности (без применения)
    ├── security_activate/  # включение SSH/UFW/fail2ban/AppArmor/auditd
    ├── logging/            # logrotate, journald, rsyslog
    ├── kernel/             # sysctl, ulimits, swap
    ├── monitoring/         # node_exporter, netdata
    ├── backup/             # restic
    └── backup_activate/    # таймеры и cron бэкапов
```

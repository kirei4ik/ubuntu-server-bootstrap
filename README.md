# Ubuntu Server Setup 2026 - Ansible Playbook

Универсальный плейбук для первичной настройки серверов Ubuntu 22.04 с акцентом на безопасность, управление логами и современные требования 2026 года.

## 🚨 КРИТИЧЕСКИ ВАЖНО: МЕРЫ ПРЕДОСТОРОЖНОСТИ

**ПЕРЕД ЗАПУСКОМ УБЕДИТЕСЬ, ЧТО:**

1. ✅ **У вас есть SSH доступ** (по ключу ИЛИ по root-паролю — оба работают!)
2. ✅ **Есть резервный доступ** (консоль управления, IPMI, KVM, VNC) — на всякий случай
3. ✅ **Вы знаете root-пароль сервера** (если входите по паролю)

### 🔄 Двухэтапный процесс:

**ЭТАП 1 (Подготовка):** Заходим под **root** (то что есть сейчас)
- playbook_prepare.yaml создаст пользователя `bestadmin` 
- Скопирует ваш SSH ключ с Mac на сервер
- **НЕ отключит root** (еще можно зайти)

**ЭТАП 2 (Активация):** Заходим под **bestadmin** (создан в Этапе 1)
- playbook_activate.yaml отключит root
- Включит фаервол
- **Только теперь root заблокирован**

### 🔧 Подготовка перед запуском:

```bash
# 1. Убедитесь что можете зайти на сервер (любым способом)
ssh root@сервер          # или
ssh -i ~/.ssh/id_rsa root@сервер

# 2. Получите ваш публичный ключ с Mac (для group_vars/all/vault.yml)
cat ~/.ssh/id_ed25519.pub  # или: cat ~/.ssh/id_rsa.pub
# Скопируйте вывод — это ваш vault_admin_ssh_key

# 3. Сделайте бэкап конфигураций (на всякий случай)
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)
sudo cp /etc/ufw/ufw.conf /etc/ufw/ufw.conf.backup.$(date +%Y%m%d)
```

### ⚠️ ВАЖНО: Inventory меняется между этапами!

```yaml
# inventory.yaml — ЭТАП 1 (подготовка):
ansible_user: root           # ← Есть сейчас
# ansible_ssh_pass: ваш-пароль  # ← Если входите по паролю (не ключу)

# inventory.yaml — ЭТАП 2 (активация):
# Поменяйте root → bestadmin ПОСЛЕ успешного playbook_prepare.yaml!
ansible_user: bestadmin      # ← Создан в prepare
```

```bash
ansible-playbook playbook_prepare.yaml --check --diff --ask-vault-pass
```

---

## 📋 Что делает этот плейбук?

### 🔐 **Безопасность (Security)**
| Сервис | Простыми словами | Зачем нужен |
|--------|------------------|-------------|
| **UFW (Firewall)** | Цифровой шлагбаум | Блокирует все порты кроме разрешённых (SSH, HTTP, HTTPS) |
| **fail2ban** | Охранник у двери | Банит IP после нескольких неудачных попыток входа |
| **AppArmor** | Клетка для программ | Не даёт программе делать то, что не разрешено |
| **SSH Hardening** | Усиленная дверь | Запрещает вход под root, требует ключи вместо паролей |
| **auditd** | Камера наблюдения | Записывает кто и что делал в системе |

### 📊 **Управление логами (Logging)**
| Сервис | Простыми словами | Зачем нужен |
|--------|------------------|-------------|
| **logrotate** | Уборщик логов | Автоматически сжимает и удаляет старые логи |
| **journald** | Журнал событий | Собирает все логи в одном месте |
| **Ограничение логов** | Контроль диска | Не даёт логам занять весь диск |

### ⚙️ **Оптимизация системы (Kernel)**
| Сервис | Простыми словами | Зачем нужен |
|--------|------------------|-------------|
| **sysctl** | Настройки "под капотом" | Оптимизирует работу сети и памяти |
| **ulimits** | Лимиты ресурсов | Ограничивает процессы пользователей |
| **swap** | Виртуальная память | Дополнительная память на диске |

### 📈 **Мониторинг (Monitoring)** — опционально, запускается отдельно
| Сервис | Простыми словами | Зачем нужен |
|--------|------------------|-------------|
| **node_exporter** | Датчики системы | Собирает метрики CPU, памяти, диска по HTTP порту 9100 (для Prometheus/Grafana) |
| **health-check.sh** | Врач системы | Каждые 15 мин проверяет диск, память, CPU, SSH и пишет в лог |
| **Netdata** | Веб-дашборд | Реальное время — графики в браузере на порту 19999 (включается вручную) |

### 💾 **Бэкапы (Backup)** — опционально, запускается отдельно
| Сервис | Простыми словами | Зачем нужен |
|--------|------------------|-------------|
| **restic** | Фотограф системы | Делает снимки состояния системы |
| **Шифрование** | Замок на архиве | Защищает бэкапы от чтения |
| **Верификация** | Проверка фото | Убеждается что фото не испорчено |
| **Systemd timer** | Будильник | Автоматически делает бэкап каждый день в 04:00 |

---

## 🚀 Быстрый старт

### 1. Установите Ansible (на управляющей машине)

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ansible git

# Проверьте версию
ansible --version
```

### 2. Клонируйте репозиторий

```bash
git clone <ваш-репозиторий>
cd ubuntu-server-setup-2026
```

### 3. Настройте инвентори

Отредактируйте `inventory.yaml`:

```yaml
all:
  hosts:
    ваш-сервер:
      ansible_host: 192.168.1.100
      ansible_user: root              # ← под root при первом запуске!
      ansible_port: 22
```

### 4. Создайте файл с секретами

```bash
# Скопируйте пример
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Отредактируйте vault.yml (ваши реальные данные)
vim group_vars/all/vault.yml

# Содержимое vault.yml:
# vault_admin_ssh_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
# vault_restic_password: "ваш-пароль-из-bitwarden"
# vault_admin_email: "ваш@email.com"

# Зашифруйте файл
ansible-vault encrypt group_vars/all/vault.yml
# Введите пароль из Bitwarden
```

### 5. Настройте конфигурацию

```bash
# Скопируйте пример
cp group_vars/all.yaml.example group_vars/all.yaml

# Отредактируйте group_vars/all.yaml
vim group_vars/all.yaml
```

### 6. Запустите в тестовом режиме

```bash
# Проверить без изменений
ansible-playbook playbook_prepare.yaml --check --diff --ask-vault-pass
```

### 7. Запустите подготовку

```bash
ansible-playbook playbook_prepare.yaml --ask-vault-pass
```

### 8. Проверьте SSH доступ

```bash
# Обязательно проверьте!
ssh -i ~/.ssh/id_ed25519 bestadmin@ВАШ_СЕРВЕР
sudo ls /
```

### 9. Поменяйте inventory.yaml (ВАЖНО!)

```bash
# Отредактируйте inventory.yaml
vim inventory.yaml

# Замените:
# ansible_user: root  →  ansible_user: bestadmin
# Уберите: ansible_ssh_pass (если был)
```

### 10. Запустите активацию

```bash
ansible-playbook playbook_activate.yaml --ask-vault-pass
```

### 11. (Опционально) Настройте мониторинг

```bash
ansible-playbook playbook_monitoring.yaml --check --diff --ask-vault-pass
ansible-playbook playbook_monitoring.yaml --ask-vault-pass
```

Проверка:
```bash
# На сервере — метрики node_exporter
curl http://localhost:9100/metrics

# Скрипт проверки здоровья
sudo /usr/local/sbin/health-check.sh
```

### 12. (Опционально) Настройте бэкапы

```bash
ansible-playbook playbook_backup.yaml --check --diff --ask-vault-pass
ansible-playbook playbook_backup.yaml --ask-vault-pass
```

Проверка:
```bash
# На сервере
sudo systemctl status restic-backup.timer
sudo restic snapshots --repo /backup/repository --password-file /etc/backup/restic-password
```

---

## 📁 Структура проекта

```
ubuntu-server-setup-2026/
├── ansible.cfg            # Конфигурация Ansible
├── inventory.yaml         # Описание серверов
├── playbook_prepare.yaml  # Этап 1: Подготовка (безопасно)
├── playbook_activate.yaml # Этап 2: Активация (безопасность!)
├── playbook_monitoring.yaml  # Опционально: мониторинг (node_exporter)
├── playbook_backup.yaml   # Опционально: бэкапы (restic)
├── playbook.yaml          # Полный плейбук (все роли разом)
├── group_vars/
│   ├── all.yaml           # Ваша конфигурация
│   ├── all.yaml.example   # Пример конфигурации
│   └── all/
│       ├── vault.yml          # Зашифрованные секреты
│       └── vault.yml.example  # Шаблон секретов
├── host_vars/             # Уникальные секреты для конкретных серверов
│   └── webserver-prod/
│       └── vault.yml
├── roles/
│   ├── common/            # Базовая настройка (пользователи, пакеты)
│   ├── security/          # Подготовка безопасности (НЕ активация)
│   ├── security_activate/ # Активация SSH, UFW, fail2ban
│   ├── logging/           # Управление логами
│   ├── kernel/            # Оптимизация ядра (sysctl, limits)
│   ├── monitoring/        # 📊 Мониторинг — запускается отдельно
│   ├── backup/            # 💾 Бэкапы — запускается отдельно
│   └── backup_activate/   # Активация restic таймеров
└── tests/
    └── test-playbook.yaml
```

---

## 👥 КАСТОМИЗАЦИЯ: Пользователи и пароли

### Workflow:
1. **Секреты** → `group_vars/all/vault.yml` (зашифровать vault)
2. **Конфигурация** → `group_vars/all.yaml` (ссылается на секреты)
3. **Запуск** → `ansible-playbook --ask-vault-pass`

### Изменить имя пользователя по умолчанию:

```yaml
# group_vars/all.yaml
system:
  users:
    - name: "yourname"           # ← ИЗМЕНИТЕ ЗДЕСЬ
      ssh_key: "{{ vault_admin_ssh_key }}"
      groups: ["sudo"]
      shell: "/bin/bash"
```

### Добавить несколько пользователей:

```yaml
# 1. Добавьте ключи в group_vars/all/vault.yml:
vault_admin_ssh_key: "ssh-ed25519 AAA..."
vault_developer_ssh_key: "ssh-rsa AAA..."
vault_monitoring_ssh_key: "ssh-ed25519 AAA..."

# 2. Настройте пользователей в group_vars/all.yaml:
system:
  users:
    - name: "bestadmin"
      ssh_key: "{{ vault_admin_ssh_key }}"
      groups: ["sudo"]
      shell: "/bin/bash"
    
    - name: "developer"
      ssh_key: "{{ vault_developer_ssh_key }}"  # ← новый ключ
      groups: ["sudo", "docker"]
      shell: "/bin/zsh"
    
    - name: "monitoring"
      ssh_key: "{{ vault_monitoring_ssh_key }}"
      groups: ["sudo", "adm"]
      shell: "/bin/bash"
```

### Использовать пароли вместо ключей (НЕ рекомендуется!):

```bash
# Сгенерируйте хеш пароля (на сервере или Mac):
mkpasswd --method=SHA-512 ваш_пароль
# → $6$rounds=656000$salt$hash...

# Добавьте в group_vars/all/vault.yml:
vault_user_password: "$6$rounds=656000$salt$hash..."

# Используйте в group_vars/all.yaml:
system:
  users:
    - name: "admin"
      password: "{{ vault_user_password }}"   # ← пароль вместо ключа
      groups: ["sudo"]
```

### Изменить SSH порт:

```yaml
# group_vars/all.yaml
security:
  ssh:
    port: 2222                    # ← новый порт
    disable_root: true
    password_auth: false
```

### Добавить правила фаервола:

```yaml
# group_vars/all.yaml
security:
  firewall:
    rules:
      - port: "2222"              # ← если поменяли SSH порт
        proto: "tcp"
        comment: "SSH custom"
      - port: "8080"                # ← дополнительный порт
        proto: "tcp"
        comment: "Custom app"
```

---

## ⚙️ Настройка переменных

### Основные переменные для настройки:

1. **Пользователи и доступ** (`group_vars/all.yaml`):
   ```yaml
   system:
     users:
       - name: "admin"
         ssh_key: "{{ vault_admin_ssh_key }}"
         groups: ["sudo"]
   ```

2. **Безопасность SSH**:
   ```yaml
   security:
     ssh:
       port: 22                    # Порт SSH
       disable_root: true          # Запретить вход root
       password_auth: false        # Только по ключам
   ```

3. **Фаервол**:
   ```yaml
   security:
     firewall:
       rules:
         - port: "22"
           proto: "tcp"
           comment: "SSH"
         - port: "80"
           proto: "tcp"
           comment: "HTTP"
         - port: "443"
           proto: "tcp"
           comment: "HTTPS"
   ```

4. **Логи**:
   ```yaml
   logging:
     journald:
       system_max_use: "500M"    # Максимум 500MB для логов
     logrotate:
       maxsize: "100M"           # Максимальный размер файла лога
       rotate: 7                 # Хранить 7 архивов
   ```

5. **Бэкапы**:
   ```yaml
   backup:
     enabled: true
     include:
       directories:
         - "/etc"
         - "/home/*/.ssh"
         - "/root/.ssh"
   ```

---

## 🔧 Расширенное использование

### Запуск отдельных ролей

```bash
# Только безопасность
ansible-playbook playbook_prepare.yaml --tags "security"

# Только логи
ansible-playbook playbook_prepare.yaml --tags "logging"

# Отдельно мониторинг (не через prepare)
ansible-playbook playbook_monitoring.yaml --tags "node_exporter"

# Отдельно бэкапы (не через prepare)
ansible-playbook playbook_backup.yaml --tags "scripts"
```

### Проверка конкретного хоста

```bash
ansible-playbook playbook_prepare.yaml -l ваш-сервер --check --diff --ask-vault-pass
```

### Сухой запуск (без изменений)

```bash
ansible-playbook playbook_prepare.yaml --check --diff --ask-vault-pass
```

### Просмотр переменных

```bash
ansible-inventory -i inventory.yaml --list
ansible-inventory -i inventory.yaml --host ваш-сервер
```

---

## 🏗️ Масштабирование: несколько серверов

Когда добавится второй сервер, используйте **автоматический поиск Ansible**:

```
group_vars/
├── all/
│   └── vault.yml          ← общие секреты для ВСЕХ (SSH-ключ админа, email)
├── production/
│   └── vault.yml          ← секреты группы production (restic-пароль)
├── staging/
│   └── vault.yml          ← секреты группы staging (другой restic-пароль)
host_vars/
├── webserver-prod/
│   └── vault.yml          ← уникальные секреты только для этого сервера
└── dbserver-prod/
    └── vault.yml          ← уникальные секреты для БД
```

**Ansible автоматически** подгружает нужный vault в зависимости от хоста/группы. Никаких `vars_files` в плейбуках прописывать не нужно.

### Когда что использовать:
| Случай | Куда класть |
|--------|-------------|
| Один и тот же SSH-ключ на все сервера | `group_vars/all/vault.yml` |
| Разный restic-пароль для prod и staging | `group_vars/production/vault.yml` vs `group_vars/staging/vault.yml` |
| Уникальный токен только на одном сервере | `host_vars/имя_хоста/vault.yml` |
| На сервере БД другие SSH-ключи | `host_vars/dbserver/vault.yml` (переопределит групповой) |

### Добавление нового сервера (пошагово):

```bash
# 1. Добавьте сервер в inventory.yaml
vim inventory.yaml

# 2. Если у него уникальные секреты — создайте папку:
mkdir -p host_vars/newserver

# 3. Скопируйте и отредактируйте:
cp group_vars/all/vault.yml host_vars/newserver/vault.yml
ansible-vault edit host_vars/newserver/vault.yml

# 4. Запустите на конкретном сервере:
ansible-playbook playbook_prepare.yaml -l newserver --ask-vault-pass
```

### Разные пароли шифрования для разных сред:

```bash
# Зашифровать с меткой (vault-id):
ansible-vault encrypt --vault-id prod group_vars/production/vault.yml
ansible-vault encrypt --vault-id staging group_vars/staging/vault.yml

# При запуске указать нужный пароль:
ansible-playbook playbook_prepare.yaml --vault-id prod@prompt
```

---

## 🩺 TROUBLESHOOTING (Решение проблем)

### Проблема 1: "SSH доступ потерян после активации"

**Причина:** playbook_activate.yaml заблокировал root или ключи не работают.

**Решение:**
```bash
# Через консоль управления (IPMI/KVM):
sudo cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
sudo systemctl restart ssh

# Или перезапустите с параметром PermitRootLogin yes:
sudo sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

---

### Проблема 2: "ansible-playbook просит vault password"

**Причина:** Файл vault.yml не зашифрован или забыли флаг.

**Решение:**
```bash
# Если ещё не зашифрован:
ansible-vault encrypt group_vars/all/vault.yml

# При запуске укажите пароль:
ansible-playbook playbook_prepare.yaml --ask-vault-pass

# Или создайте файл с паролем (менее безопасно):
echo "ваш-пароль" > .vault_pass
chmod 600 .vault_pass
ansible-playbook playbook_prepare.yaml --vault-password-file .vault_pass
```

---

### Проблема 3: "Restic init запрашивает пароль интерактивно"

**Причина:** Репозиторий не инициализирован или пароль неправильный.

**Решение:**
```bash
# На сервере:
sudo cat /etc/backup/restic-password   # Проверить файл с паролем
sudo restic init --repo /backup/repository --password-file /etc/backup/restic-password

# Если пароль не работает — сбросьте репозиторий:
sudo rm -rf /backup/repository/*
sudo restic init --repo /backup/repository --password-file /etc/backup/restic-password
```

---

### Проблема 4: "Fail2ban забанил мой IP"

**Причина:** Слишком много неудачных попыток входа.

**Решение:**
```bash
# На сервере (через консоль):
sudo fail2ban-client set sshd unbanip ВАШ_IP

# Или остановите fail2ban:
sudo systemctl stop fail2ban
```

---

### Проблема 5: "UFW заблокировал SSH порт"

**Причина:** Неправильно настроены правила фаервола.

**Решение:**
```bash
# Через консоль управления:
sudo ufw disable
sudo ufw reset
sudo ufw default allow incoming
sudo ufw allow 22/tcp
sudo ufw enable
```

---

### Проблема 6: "Ошибка: vault_admin_ssh_key is undefined"

**Причина:** Переменная из group_vars/all/vault.yml не найдена.

**Решение:**
```bash
# 1. Проверьте vault.yml:
ansible-vault view group_vars/all/vault.yml

# 2. Убедитесь что vault_admin_ssh_key задан:
grep vault_admin_ssh_key group_vars/all/vault.yml

# 3. Если отсутствует — добавьте:
# vault_admin_ssh_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."

# 4. Перешифруйте:
ansible-vault encrypt group_vars/all/vault.yml
```

---

### Проблема 7: "Permission denied при SSH подключении"

**Причина:** Ключ не скопирован или неправильные права.

**Решение:**
```bash
# На сервере (через root или консоль):
sudo ls -la /home/bestadmin/.ssh/
sudo cat /home/bestadmin/.ssh/authorized_keys

# Если пусто — скопируйте ключ вручную:
sudo mkdir -p /home/bestadmin/.ssh
sudo chmod 700 /home/bestadmin/.ssh
sudo bash -c 'echo "ssh-ed25519 AAA..." > /home/bestadmin/.ssh/authorized_keys'
sudo chmod 600 /home/bestadmin/.ssh/authorized_keys
sudo chown -R bestadmin:bestadmin /home/bestadmin/.ssh
```

---

## 📊 Проверка после установки

После запуска плейбука проверьте:

```bash
# Проверьте SSH
ssh user@server

# Проверьте фаервол
sudo ufw status verbose

# Проверьте fail2ban
sudo fail2ban-client status

# Проверьте AppArmor
sudo apparmor_status

# Проверьте логи
sudo journalctl --disk-usage
sudo ls -la /var/log/

# Проверьте бэкапы
sudo restic snapshots --password-file /etc/backup/restic-password
```

---

## 🤝 Вклад в проект

1. Форкните репозиторий
2. Создайте ветку для вашей фичи
3. Внесите изменения
4. Напишите тесты
5. Создайте Pull Request

---

## 📄 Лицензия

MIT License

---

## ❓ FAQ

**Q: Можно ли использовать на Ubuntu 20.04/24.04?**
**A:** Да, но тестировалось на 22.04. Могут быть различия в версиях пакетов.

**Q: Как отключить определённую функциональность?**
**A:** Измените переменные в `group_vars/all.yaml`:
```yaml
backup:
  enabled: false  # Отключить бэкапы

monitoring:
  node_exporter:
    enabled: false  # Отключить мониторинг
```

**Q: Где хранятся секретные данные?**
**A:** В `group_vars/all/vault.yml`, зашифрованном через Ansible Vault. Для уникальных секретов отдельных серверов используйте `host_vars/имя_хоста/vault.yml`.

**Q: Как добавить свой сервис в мониторинг?**
**A:** Добавьте коллектор в `monitoring.node_exporter.collectors.enabled`.

**Q: Как настроить удалённое хранилище для бэкапов?**
**A:** Включите `backup.remote_storage.enabled` и настройте параметры.

**Q: Как изменить пользователя или пароль?**
**A:** 
1. Отредактируйте `group_vars/all.yaml` (имя пользователя)
2. Отредактируйте `group_vars/all/vault.yml` (пароли, ключи)
3. Зашифруйте `ansible-vault encrypt group_vars/all/vault.yml`
4. Запустите `ansible-playbook playbook_prepare.yaml --ask-vault-pass`

---

## 📞 Поддержка

При возникновении проблем:
1. Проверьте запуск в тестовом режиме: `--check --diff`
2. Проверьте логи Ansible: добавить `-vvv`
3. Убедитесь что есть резервный доступ к серверу
4. Создайте issue в репозитории

---

**ВАЖНО:** Этот плейбук вносит критические изменения в систему. Всегда тестируйте на тестовом окружении перед применением на production!

#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-bootstrap.XXXXXX")"
INVENTORY_FILE="$TMP_DIR/inventory.yml"
VARS_FILE="$TMP_DIR/vars.yml"
trap 'rm -rf "$TMP_DIR"' EXIT
umask 077

die() {
  echo "Ошибка: $*" >&2
  exit 1
}

quote_yaml() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

valid_hostname() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]
}

valid_public_key() {
  [[ "$1" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-[^[:space:]]+|sk-[^[:space:]]+)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]]+.*)?$ ]]
}

command -v ansible-playbook >/dev/null 2>&1 || die "не найден ansible-playbook"
command -v ssh >/dev/null 2>&1 || die "не найден ssh"

read -r -p "IP или hostname сервера: " SERVER_ADDRESS
[[ -n "$SERVER_ADDRESS" ]] || die "адрес сервера не может быть пустым"

read -r -p "Root-пользователь [root]: " ROOT_USER
ROOT_USER="${ROOT_USER:-root}"
read -r -s -p "Пароль пользователя $ROOT_USER: " ROOT_PASSWORD
printf '\n'
[[ -n "$ROOT_PASSWORD" ]] || die "пароль не может быть пустым"

DEFAULT_HOSTNAME="${SERVER_ADDRESS//./-}"
read -r -p "Hostname [$DEFAULT_HOSTNAME]: " SERVER_HOSTNAME
SERVER_HOSTNAME="${SERVER_HOSTNAME:-$DEFAULT_HOSTNAME}"
valid_hostname "$SERVER_HOSTNAME" || die "некорректный hostname"

read -r -p "Имя основного администратора [bestadmin]: " PRIMARY_USER
PRIMARY_USER="${PRIMARY_USER:-bestadmin}"
valid_username "$PRIMARY_USER" || die "некорректное имя пользователя"

read -r -p "Публичный SSH-ключ для $PRIMARY_USER: " PRIMARY_KEY
valid_public_key "$PRIMARY_KEY" || die "некорректный формат публичного SSH-ключа"

USERS_YAML="  - name: $(quote_yaml "$PRIMARY_USER")\n    ssh_key: $(quote_yaml "$PRIMARY_KEY")\n    groups: [\"sudo\"]\n    shell: /bin/bash\n"
USERS_SUMMARY="  - $PRIMARY_USER (admin)\n"

while true; do
  read -r -p "Добавить ещё пользователя? [y/N]: " ADD_USER
  case "${ADD_USER:-N}" in
    y|Y|yes|Yes)
      read -r -p "Имя пользователя: " USER_NAME
      valid_username "$USER_NAME" || die "некорректное имя пользователя"
      [[ "$USER_NAME" != "$PRIMARY_USER" ]] || die "пользователь уже добавлен"
      read -r -p "Роль (admin/user) [user]: " USER_ROLE
      USER_ROLE="${USER_ROLE:-user}"
      [[ "$USER_ROLE" == "admin" || "$USER_ROLE" == "user" ]] || die "роль должна быть admin или user"
      read -r -p "Публичный SSH-ключ для $USER_NAME: " USER_KEY
      valid_public_key "$USER_KEY" || die "некорректный формат публичного SSH-ключа"
      if [[ "$USER_ROLE" == "admin" ]]; then
        USER_GROUPS='["sudo"]'
      else
        USER_GROUPS='[]'
      fi
      USERS_YAML+="  - name: $(quote_yaml "$USER_NAME")\n    ssh_key: $(quote_yaml "$USER_KEY")\n    groups: $USER_GROUPS\n    shell: /bin/bash\n"
      USERS_SUMMARY+="  - $USER_NAME ($USER_ROLE)\n"
      ;;
    n|N|no|No|'')
      break
      ;;
    *)
      echo "Введите y или n."
      ;;
  esac
done

FIREWALL_RULES="  - port: '22'\n    proto: tcp\n    comment: 'SSH доступ'\n"
FIREWALL_SUMMARY="  - 22/tcp — SSH (обязательно)\n"
while true; do
  read -r -p "Добавить входящий порт? [y/N]: " ADD_PORT
  case "${ADD_PORT:-N}" in
    y|Y|yes|Yes)
      read -r -p "Порт (например 80 или 443): " PORT
      [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die "некорректный порт"
      read -r -p "Протокол (tcp/udp) [tcp]: " PROTO
      PROTO="${PROTO:-tcp}"
      [[ "$PROTO" == "tcp" || "$PROTO" == "udp" ]] || die "протокол должен быть tcp или udp"
      read -r -p "Комментарий [custom]: " COMMENT
      COMMENT="${COMMENT:-custom}"
      FIREWALL_RULES+="  - port: $(quote_yaml "$PORT")\n    proto: $(quote_yaml "$PROTO")\n    comment: $(quote_yaml "$COMMENT")\n"
      FIREWALL_SUMMARY+="  - $PORT/$PROTO — $COMMENT\n"
      ;;
    n|N|no|No|'')
      break
      ;;
    *)
      echo "Введите y или n."
      ;;
  esac
done

cat >"$INVENTORY_FILE" <<EOF
all:
  hosts:
    target:
      ansible_host: $(quote_yaml "$SERVER_ADDRESS")
      ansible_user: $(quote_yaml "$ROOT_USER")
      ansible_password: $(quote_yaml "$ROOT_PASSWORD")
      ansible_port: 22
EOF

{
  printf 'bootstrap_hostname: %s\n' "$(quote_yaml "$SERVER_HOSTNAME")"
  printf 'bootstrap_users:\n'
  printf '%b' "$USERS_YAML"
  printf 'bootstrap_firewall_rules:\n'
  printf '%b' "$FIREWALL_RULES"
} >"$VARS_FILE"

cat <<EOF

Будет настроен сервер:
  Адрес: $SERVER_ADDRESS
  Hostname: $SERVER_HOSTNAME

Пользователи:
$(printf '%b' "$USERS_SUMMARY")
SSH после настройки:
  root SSH: запрещён
  Вход по паролю: запрещён
  Вход: только по SSH-ключам

UFW — разрешённые входящие подключения:
$(printf '%b' "$FIREWALL_SUMMARY")
Все дополнительные порты добавляются к обязательному SSH-порту 22.

Будут применены:
  - UFW, fail2ban, auditd, AppArmor
  - timezone, locale, chrony
  - logrotate/journald, sysctl и swap
  - обновление системы

Будут установлены:
  curl, git, htop, vim, tmux, ufw, fail2ban,
  apparmor, auditd, chrony, logrotate, rsync, ca-certificates

Monitoring: не устанавливается
Backup: не устанавливается
EOF

read -r -p "Начать настройку? [y/N]: " CONFIRM
[[ "${CONFIRM:-N}" =~ ^([yY]|[yY][eE][sS])$ ]] || { echo "Настройка отменена."; exit 0; }

echo "[1/7] Подготавливаем сервер и создаём пользователей"
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
  -i "$INVENTORY_FILE" \
  "$PROJECT_DIR/playbook_bootstrap_prepare.yaml" \
  -e "@$VARS_FILE"

echo "[2/7] Проверяем SSH-вход под $PRIMARY_USER"
ssh -o BatchMode=yes -o ConnectTimeout=10 -o PasswordAuthentication=no \
  -o StrictHostKeyChecking=no "$PRIMARY_USER@$SERVER_ADDRESS" true \
  || die "не удалось войти под $PRIMARY_USER. Проверьте, что соответствующий приватный ключ доступен ssh-agent или стандартному SSH-клиенту"

cat >"$INVENTORY_FILE" <<EOF
all:
  hosts:
    target:
      ansible_host: $(quote_yaml "$SERVER_ADDRESS")
      ansible_user: $(quote_yaml "$PRIMARY_USER")
      ansible_port: 22
EOF

echo "[3/7] Применяем SSH hardening, UFW и security-сервисы"
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
  -i "$INVENTORY_FILE" \
  "$PROJECT_DIR/playbook_bootstrap_harden.yaml" \
  -e "@$VARS_FILE"

echo "[4/7] Проверяем доступ под $PRIMARY_USER после hardening"
ssh -o BatchMode=yes -o ConnectTimeout=10 -o PasswordAuthentication=no \
  -o StrictHostKeyChecking=no "$PRIMARY_USER@$SERVER_ADDRESS" true \
  || die "SSH-проверка после hardening не прошла"

echo "[5/7] Проверяем UFW"
ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$PRIMARY_USER@$SERVER_ADDRESS" \
  'sudo ufw status verbose'

echo "[6/7] Проверяем fail2ban и auditd"
ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$PRIMARY_USER@$SERVER_ADDRESS" \
  'systemctl is-active fail2ban; systemctl is-active auditd'

echo "[7/7] Настройка завершена"
echo "Подключение: ssh $PRIMARY_USER@$SERVER_ADDRESS"

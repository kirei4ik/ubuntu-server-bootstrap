#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${TMPDIR:-/tmp}/ubuntu-bootstrap"
STATE_FILE="$STATE_DIR/state.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-bootstrap.XXXXXX")"
INVENTORY_FILE="$TMP_DIR/inventory.yml"
VARS_FILE="$TMP_DIR/vars.yml"
KNOWN_HOSTS_FILE="$TMP_DIR/known_hosts"
KEYSCAN_ERROR_FILE="$TMP_DIR/known_hosts.error"
trap 'rm -rf "$TMP_DIR"' EXIT
umask 077
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

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

save_input_state() {
  local state_tmp="${STATE_FILE}.tmp.$$"
  declare -p SERVER_ADDRESS ROOT_USER ROOT_PASSWORD SERVER_HOSTNAME \
    PRIMARY_USER PRIMARY_KEY USERS_YAML USERS_SUMMARY FIREWALL_RULES FIREWALL_SUMMARY \
    BOOTSTRAP_STEP \
    >"$state_tmp"
  chmod 600 "$state_tmp"
  mv -f "$state_tmp" "$STATE_FILE"
}

run_ansible_with_retry() {
  local log_file="$TMP_DIR/ansible-attempt.log"
  local attempt=1
  local max_attempts=3

  while (( attempt <= max_attempts )); do
    if ANSIBLE_HOST_KEY_CHECKING=True \
      ANSIBLE_SSH_ARGS="-o UserKnownHostsFile=$KNOWN_HOSTS_FILE -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ConnectionAttempts=3 -o ControlMaster=auto -o ControlPersist=60s -o ControlPath=/tmp/ansible-ssh-%h-%p-%r" \
      ansible-playbook "$@" 2>&1 | tee "$log_file"; then
      return 0
    fi

    if (( attempt == max_attempts )) || \
      ! grep -Eq 'UNREACHABLE|Failed to connect to the host via ssh|Connection refused|Connection timed out' "$log_file"; then
      return 1
    fi

    echo "SSH-соединение временно прервано. Повторная попытка через 10 секунд ($((attempt + 1))/$max_attempts)..." >&2
    sleep 10
    attempt=$((attempt + 1))
  done
}

command -v ansible-playbook >/dev/null 2>&1 || die "не найден ansible-playbook"
command -v ssh >/dev/null 2>&1 || die "не найден ssh"
command -v ssh-keyscan >/dev/null 2>&1 || die "не найден ssh-keyscan"
command -v ssh-keygen >/dev/null 2>&1 || die "не найден ssh-keygen"

RESUME_STATE=false
if [[ -f "$STATE_FILE" ]]; then
  echo "Найдены сохранённые данные незавершённого bootstrap."
  read -r -p "Продолжить с ними? [Y/n]: " RESUME_CONFIRM
  if [[ ! "${RESUME_CONFIRM:-Y}" =~ ^([nN]|[nN][oO])$ ]]; then
    # The file is created by this script with mode 0600 in a mode 0700 directory.
    source "$STATE_FILE"
    if [[ -z "${BOOTSTRAP_STEP:-}" ]]; then
      echo "Это сохранение создано старой версией bootstrap без checkpoint-этапов."
      read -r -p "Подготовка сервера уже завершилась успешно? [y/N]: " PREPARE_DONE
      if [[ "${PREPARE_DONE:-N}" =~ ^([yY]|[yY][eE][sS])$ ]]; then
        BOOTSTRAP_STEP="prepare_done"
      else
        BOOTSTRAP_STEP="input_saved"
      fi
      save_input_state
    fi
    RESUME_STATE=true
  else
    rm -f "$STATE_FILE"
  fi
fi

if [[ "$RESUME_STATE" == false ]]; then
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
    read -r -p "Добавить дополнительный входящий порт (кроме SSH 22/tcp)? [y/N]: " ADD_PORT
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

  BOOTSTRAP_STEP="input_saved"
  save_input_state
  echo "Введённые данные сохранены во временный файл для возможности продолжить."
fi

echo
echo "Проверка host key сервера"
if ! ssh-keyscan -T 10 -t ed25519,ecdsa,rsa "$SERVER_ADDRESS" \
  >"$KNOWN_HOSTS_FILE" 2>"$KEYSCAN_ERROR_FILE"; then
  echo "Не удалось получить host key сервера." >&2
  if [[ -s "$KEYSCAN_ERROR_FILE" ]]; then
    echo "Причина от ssh-keyscan:" >&2
    sed 's/^/  /' "$KEYSCAN_ERROR_FILE" >&2
  fi
  echo "Проверьте адрес сервера, доступность TCP-порта 22 и запущенный SSH-сервис." >&2
  exit 1
fi
[[ -s "$KNOWN_HOSTS_FILE" ]] || die "сервер не вернул host key"
echo "Полученные fingerprints:"
ssh-keygen -lf "$KNOWN_HOSTS_FILE" -E sha256
read -r -p "Сверьте fingerprint с панелью провайдера и подтвердите? [y/N]: " HOST_KEY_CONFIRM
[[ "${HOST_KEY_CONFIRM:-N}" =~ ^([yY]|[yY][eE][sS])$ ]] \
  || { echo "Настройка отменена: host key не подтверждён."; exit 0; }

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

if [[ "$BOOTSTRAP_STEP" == "input_saved" ]]; then
  echo "[1/8] Подготавливаем сервер и создаём пользователей"
  run_ansible_with_retry \
    -i "$INVENTORY_FILE" \
    "$PROJECT_DIR/playbook_bootstrap_prepare.yaml" \
    -e "@$VARS_FILE"
  BOOTSTRAP_STEP="prepare_done"
  save_input_state
fi

if [[ "$BOOTSTRAP_STEP" == "prepare_done" ]]; then
  echo "[2/8] Проверяем SSH-вход под $PRIMARY_USER"
  ssh -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=3 -o PasswordAuthentication=no \
    -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" -o StrictHostKeyChecking=yes \
    "$PRIMARY_USER@$SERVER_ADDRESS" true \
    || die "не удалось войти под $PRIMARY_USER. Проверьте, что соответствующий приватный ключ доступен ssh-agent или стандартному SSH-клиенту"
  BOOTSTRAP_STEP="admin_login_done"
  save_input_state
fi

cat >"$INVENTORY_FILE" <<EOF
all:
  hosts:
    target:
      ansible_host: $(quote_yaml "$SERVER_ADDRESS")
      ansible_user: $(quote_yaml "$PRIMARY_USER")
      ansible_port: 22
EOF

if [[ "$BOOTSTRAP_STEP" == "admin_login_done" ]]; then
  echo "[3/8] Применяем SSH hardening, UFW и security-сервисы"
  run_ansible_with_retry \
    -i "$INVENTORY_FILE" \
    "$PROJECT_DIR/playbook_bootstrap_harden.yaml" \
    -e "@$VARS_FILE"
  BOOTSTRAP_STEP="harden_done"
  save_input_state
fi

if [[ "$BOOTSTRAP_STEP" == "harden_done" ]]; then
  echo "[4/8] Проверяем доступ под $PRIMARY_USER после hardening"
  ssh -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=3 -o PasswordAuthentication=no \
    -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" -o StrictHostKeyChecking=yes \
    "$PRIMARY_USER@$SERVER_ADDRESS" true \
    || die "SSH-проверка после hardening не прошла"
  BOOTSTRAP_STEP="post_harden_verified"
  save_input_state
fi

if [[ "$BOOTSTRAP_STEP" == "post_harden_verified" ]]; then
  echo "[5/8] Проверяем UFW"
  ssh -o BatchMode=yes -o ConnectionAttempts=3 -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" -o StrictHostKeyChecking=yes "$PRIMARY_USER@$SERVER_ADDRESS" \
    'sudo ufw status verbose'
  BOOTSTRAP_STEP="ufw_verified"
  save_input_state
fi

if [[ "$BOOTSTRAP_STEP" == "ufw_verified" ]]; then
  echo "[6/8] Проверяем fail2ban и auditd"
  ssh -o BatchMode=yes -o ConnectionAttempts=3 -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" -o StrictHostKeyChecking=yes "$PRIMARY_USER@$SERVER_ADDRESS" \
    'systemctl is-active fail2ban; systemctl is-active auditd'
  BOOTSTRAP_STEP="security_verified"
  save_input_state
fi

rm -f "$STATE_FILE"
echo "[7/8] Host key сохранён только во временном файле и удалён после завершения"
echo "[8/8] Настройка завершена"
echo "Подключение: ssh $PRIMARY_USER@$SERVER_ADDRESS"

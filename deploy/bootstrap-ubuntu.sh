#!/usr/bin/env bash
# First-time setup for the Aroll+ Oracle VM.
# Run on Ubuntu ARM after the VM exists:
#   sudo bash deploy/bootstrap-ubuntu.sh your-name.duckdns.org
#
# The laptop database is not touched. This script does not run the demo seed.
set -euo pipefail

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then
  echo "Usage: sudo bash deploy/bootstrap-ubuntu.sh your-name.duckdns.org" >&2
  exit 1
fi

REPO_URL="${AROLL_REPO_URL:-https://github.com/JRParreno/aroll.git}"
BRANCH="${AROLL_BRANCH:-fix/public-deploy-prep}"
APP_ROOT="${AROLL_ROOT:-/opt/aroll}"
APP_USER="${SUDO_USER:-ubuntu}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git python3 python3-venv python3-pip \
  nodejs npm docker.io docker-compose-v2 debian-keyring debian-archive-keyring \
  apt-transport-https gnupg ufw openssl

if ! command -v caddy >/dev/null 2>&1; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update
  apt-get install -y caddy
fi

usermod -aG docker "$APP_USER" || true
systemctl enable --now docker

if [[ ! -d "$APP_ROOT/.git" ]]; then
  git clone --branch "$BRANCH" "$REPO_URL" "$APP_ROOT"
fi
chown -R "$APP_USER:$APP_USER" "$APP_ROOT"

ENV_FILE="$APP_ROOT/backend/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  DB_PASSWORD="$(openssl rand -hex 24)"
  JWT_SECRET="$(openssl rand -hex 32)"
  cat >"$ENV_FILE" <<EOF
DATABASE_URL=postgresql://aroll:${DB_PASSWORD}@127.0.0.1:5432/aroll
JWT_SECRET=${JWT_SECRET}
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=480
CORS_ORIGINS=https://${DOMAIN}
CORS_ALLOW_LOCALHOST_REGEX=false
REGISTRATION_UPLOAD_DIR=uploads/registrations
CONSENT_UPLOAD_DIR=uploads/consents
SMTP_HOST=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=
SMTP_USE_TLS=true
SMTP_USE_SSL=false
OWNER_LOGIN_URL=https://${DOMAIN}/owner-login
FCM_PROJECT_ID=
FCM_SERVICE_ACCOUNT_JSON=
SCHEDULE_REMINDER_LOOP_ENABLED=true
SCHEDULE_REMINDER_INTERVAL_SECONDS=900
EOF
  chown "$APP_USER:$APP_USER" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
else
  DB_PASSWORD="$(sed -nE 's#^DATABASE_URL=postgresql://aroll:([^@]+)@.*#\1#p' "$ENV_FILE")"
fi

cd "$APP_ROOT"
POSTGRES_PASSWORD="$DB_PASSWORD" docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
for _ in $(seq 1 30); do
  docker exec aroll-db pg_isready -U aroll -d aroll && break
  sleep 2
done

sudo -u "$APP_USER" -H bash -lc "
  set -euo pipefail
  cd '$APP_ROOT/backend'
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install -r requirements.txt
  mkdir -p models uploads/registrations uploads/consents
  if [[ ! -s models/arcface_w600k_r50.onnx ]]; then
    curl -L --fail --retry 3 -o models/arcface_w600k_r50.onnx \
      https://huggingface.co/immich-app/buffalo_l/resolve/main/recognition/model.onnx
  fi
  if [[ ! -s models/face_detection_yunet_2023mar.onnx ]]; then
    curl -L --fail --retry 3 -o models/face_detection_yunet_2023mar.onnx \
      https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx
  fi
  .venv/bin/alembic upgrade head
  cd '$APP_ROOT/admin-web'
  npm install
  npm run build
"

sed "s/aroll.example.duckdns.org/${DOMAIN}/" "$APP_ROOT/deploy/Caddyfile" > /etc/caddy/Caddyfile
systemctl reload caddy || systemctl restart caddy

cp "$APP_ROOT/deploy/aroll-api.service" /etc/systemd/system/aroll-api.service
systemctl daemon-reload
systemctl enable --now aroll-api

if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
fi

echo
echo "Aroll+ API is starting on https://${DOMAIN}"
echo "Database password and JWT secret are in ${ENV_FILE} (mode 600)."
echo "Do not run python -m app.seed on this server. It loads the demo businesses."
echo "Create the platform admin separately, then change that password."

#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/opt/api-agenda"
APP_USER="agenda"
ENV_FILE="/etc/api-agenda.env"
BUNDLE="/home/ubuntu/api-agenda.tar.gz"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: ejecuta este script con sudo."
  exit 1
fi

if [ ! -f "$BUNDLE" ]; then
  echo "ERROR: no se encontro $BUNDLE"
  exit 1
fi

echo "==> Instalando paquetes base..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg nginx mysql-server tar openssl

echo "==> Instalando Node.js 22..."
if ! command -v node >/dev/null 2>&1 || [ "$(node -p 'Number(process.versions.node.split(".")[0])')" -lt 20 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi
node --version
npm --version

echo "==> Configurando swap de 2 GB..."
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> Creando usuario y directorio de la API..."
if ! id -u "$APP_USER" >/dev/null 2>&1; then
  useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
fi
mkdir -p "$APP_DIR"
find "$APP_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
tar -xzf "$BUNDLE" -C "$APP_DIR"
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

echo "==> Iniciando MySQL..."
systemctl enable --now mysql

echo "==> Preparando base de datos agenda..."
TABLE_EXISTS="$(mysql --batch --skip-column-names -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='agenda' AND table_name='eventos';")"
if [ "$TABLE_EXISTS" = "0" ]; then
  echo "Creando tablas y datos iniciales desde database/agenda.sql..."
  mysql < "$APP_DIR/database/agenda.sql"
else
  echo "La tabla eventos ya existe; se conservan los datos."
fi

DB_PASSWORD="$(openssl rand -hex 16)"
mysql <<SQL
CREATE DATABASE IF NOT EXISTS agenda CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS 'agenda_app'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER 'agenda_app'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT SELECT, INSERT, UPDATE, DELETE ON agenda.* TO 'agenda_app'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "==> Escribiendo variables de entorno..."
cat > "$ENV_FILE" <<ENV
PORT=3000
HOST=127.0.0.1
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=agenda_app
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=agenda
DB_CONNECTION_LIMIT=10
NODE_ENV=production
ENV
chmod 600 "$ENV_FILE"
chown root:root "$ENV_FILE"

echo "==> Instalando dependencias de Node..."
(
  cd "$APP_DIR"
  sudo -u "$APP_USER" -H env PATH="/usr/local/bin:/usr/bin:/bin" npm ci --omit=dev
)

echo "==> Configurando servicio systemd..."
cat > /etc/systemd/system/api-agenda.service <<'SERVICE'
[Unit]
Description=API de Agenda (Node.js)
After=network.target mysql.service
Wants=mysql.service

[Service]
Type=simple
User=agenda
Group=agenda
WorkingDirectory=/opt/api-agenda
EnvironmentFile=/etc/api-agenda.env
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable api-agenda
systemctl restart api-agenda

echo "==> Configurando Nginx..."
cat > /etc/nginx/sites-available/api-agenda <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    client_max_body_size 1m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/api-agenda /etc/nginx/sites-enabled/api-agenda
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

echo "==> Esperando que la API responda..."
API_OK=0
for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:3000/health >/dev/null 2>&1; then
    API_OK=1
    break
  fi
  sleep 1
done

if [ "$API_OK" -ne 1 ]; then
  echo "ERROR: la API no respondio. Logs:"
  journalctl -u api-agenda -n 80 --no-pager || true
  exit 1
fi

echo "==> Health check directo:"
curl -fsS http://127.0.0.1:3000/health
echo
echo "==> Health check por Nginx:"
curl -fsS http://127.0.0.1/health
echo
systemctl --no-pager --full status api-agenda || true

echo "==> Despliegue completado."

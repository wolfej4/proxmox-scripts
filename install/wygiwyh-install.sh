#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: wolfej4
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/eitchtee/WYGIWYH

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  gettext \
  libpq5
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.14" setup_uv
NODE_VERSION="24" setup_nodejs
PG_VERSION="17" setup_postgresql
PG_DB_NAME="wygiwyh" PG_DB_USER="wygiwyh" setup_postgresql_db

fetch_and_deploy_gh_release "wygiwyh" "eitchtee/WYGIWYH" "tarball" "latest" "/opt/wygiwyh"

msg_info "Configuring WYGIWYH"
mkdir -p /opt/wygiwyh-data/attachments
ln -sfn /opt/wygiwyh-data/attachments /opt/wygiwyh/app/attachments
SECRET_KEY="$(random_password 50)"
ADMIN_EMAIL="admin@wygiwyh.local"
ADMIN_PASSWORD="$(random_password 16)"
TIMEZONE="$(cat /etc/timezone 2>/dev/null || echo UTC)"
cat <<EOF >/opt/wygiwyh.env
# WYGIWYH configuration. Restart both services after changing:
#   systemctl restart wygiwyh wygiwyh-worker
TZ=${TIMEZONE}
DEBUG=false
# Space-separated, keep the quotes. Add your public URL (e.g. https://wygiwyh.example.com) when using a reverse proxy.
URL="http://${LOCAL_IP}:8000"
HTTPS_ENABLED=false
SECRET_KEY=${SECRET_KEY}
# Space-separated, keep the quotes. Add your domain (e.g. wygiwyh.example.com) when using a reverse proxy.
DJANGO_ALLOWED_HOSTS="localhost 127.0.0.1 ${LOCAL_IP}"
INTERNAL_PORT=8000
APP_VERSION=$(cat ~/.wygiwyh)

SQL_DATABASE=${PG_DB_NAME}
SQL_USER=${PG_DB_USER}
SQL_PASSWORD=${PG_DB_PASS}
SQL_HOST=localhost
SQL_PORT=5432

WEB_THREADS=4
ENABLE_SOFT_DELETE=false
KEEP_DELETED_TRANSACTIONS_FOR=365
PROCRASTINATE_WORKER_CONCURRENCY=1
CHECK_FOR_UPDATES=true

# OIDC (optional) - uncomment and fill in to enable SSO
#OIDC_CLIENT_NAME=""
#OIDC_CLIENT_ID=""
#OIDC_CLIENT_SECRET=""
#OIDC_SERVER_URL=""
#OIDC_ALLOW_SIGNUP=true
EOF
chmod 600 /opt/wygiwyh.env
msg_ok "Configured WYGIWYH"

msg_info "Installing Python Dependencies"
cd /opt/wygiwyh || exit
$STD uv sync --frozen --no-dev --no-install-project --python 3.14
msg_ok "Installed Python Dependencies"

msg_info "Building Frontend (Patience)"
cd /opt/wygiwyh/frontend || exit
$STD npm ci
$STD npm run build
msg_ok "Built Frontend"

msg_info "Setting up Database"
cd /opt/wygiwyh/app || exit
set -a
source /opt/wygiwyh.env
set +a
$STD /opt/wygiwyh/.venv/bin/python manage.py compilemessages
$STD /opt/wygiwyh/.venv/bin/python manage.py collectstatic --noinput
$STD /opt/wygiwyh/.venv/bin/python manage.py migrate --noinput
{
  echo ""
  echo "WYGIWYH Admin"
  echo "Email: ${ADMIN_EMAIL}"
  echo "Password: ${ADMIN_PASSWORD}"
} >>~/wygiwyh.creds
export ADMIN_EMAIL ADMIN_PASSWORD
$STD /opt/wygiwyh/.venv/bin/python manage.py setup_users
unset ADMIN_PASSWORD
msg_ok "Set up Database"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/wygiwyh.service
[Unit]
Description=WYGIWYH Web
After=network-online.target postgresql.service
Wants=network-online.target
Requires=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/wygiwyh/app
EnvironmentFile=/opt/wygiwyh.env
Environment=PATH=/opt/wygiwyh/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStartPre=/opt/wygiwyh/.venv/bin/python manage.py migrate --noinput
ExecStartPre=-/opt/wygiwyh/.venv/bin/python manage.py setup_oauth
ExecStart=/opt/wygiwyh/.venv/bin/gunicorn WYGIWYH.wsgi:application --bind 0.0.0.0:8000 --timeout 600 --threads \${WEB_THREADS}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat <<EOF >/etc/systemd/system/wygiwyh-worker.service
[Unit]
Description=WYGIWYH Background Worker (Procrastinate)
After=wygiwyh.service
Requires=postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/wygiwyh/app
EnvironmentFile=/opt/wygiwyh.env
Environment=PATH=/opt/wygiwyh/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/wygiwyh/.venv/bin/python manage.py procrastinate worker
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now wygiwyh
systemctl enable -q --now wygiwyh-worker
msg_ok "Created Services"

motd_ssh
customize
cleanup_lxc

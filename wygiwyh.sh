#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: wolfej4
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/eitchtee/WYGIWYH

APP="WYGIWYH"
var_tags="${var_tags:-finance}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/wygiwyh ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "wygiwyh" "eitchtee/WYGIWYH"; then
    msg_info "Stopping Services"
    systemctl stop wygiwyh-worker wygiwyh
    msg_ok "Stopped Services"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "wygiwyh" "eitchtee/WYGIWYH" "tarball" "latest" "/opt/wygiwyh"
    PYTHON_VERSION="3.14" setup_uv
    NODE_VERSION="24" setup_nodejs

    msg_info "Updating ${APP}"
    ln -sfn /opt/wygiwyh-data/attachments /opt/wygiwyh/app/attachments
    cd /opt/wygiwyh || exit
    $STD uv sync --frozen --no-dev --no-install-project --python 3.14
    cd /opt/wygiwyh/frontend || exit
    $STD npm ci
    $STD npm run build
    sed -i "s/^APP_VERSION=.*/APP_VERSION=$(cat ~/.wygiwyh)/" /opt/wygiwyh.env
    cd /opt/wygiwyh/app || exit
    set -a
    source /opt/wygiwyh.env
    set +a
    $STD /opt/wygiwyh/.venv/bin/python manage.py compilemessages
    $STD /opt/wygiwyh/.venv/bin/python manage.py collectstatic --noinput
    $STD /opt/wygiwyh/.venv/bin/python manage.py migrate --noinput
    msg_ok "Updated ${APP}"

    msg_info "Starting Services"
    systemctl start wygiwyh wygiwyh-worker
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
echo -e "${INFO}${YW} Admin login is saved in ~/wygiwyh.creds inside the container${CL}"

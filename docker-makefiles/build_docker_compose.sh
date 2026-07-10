#!/usr/bin/env bash

# -------- Helpers --------
die() {
  echo "Error: $1" >&2
  exit "${2:-1}"
}

OS_TYPE=$(uname -s)

# WSL reports uname -s as Linux; detect it for compose template auto-selection.
_is_wsl() {
  if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    return 0
  fi
  if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    return 0
  fi
  return 1
}

# Auto-select ports-based compose on WSL, macOS, and other non-native-Linux hosts.
_auto_use_ports_template() {
  if [[ "${OS_TYPE}" == "Darwin" ]]; then
    return 0
  fi
  if _is_wsl; then
    return 0
  fi
  if [[ "${OS_TYPE}" != "Linux" ]]; then
    return 0
  fi
  return 1
}

if [[ "$OS_TYPE" == "Darwin" ]]; then
  SED_INPLACE="sed -i .bak"
else
  SED_INPLACE="sed -i.bak"
fi

# -------- Args --------
NODE_CONFIGS=${1:-anylog-generic}
TAG=${2:-latest}
DEPLOYMENT_TYPE=${3:-docker}
export TAG

if [[ "${DEPLOYMENT_TYPE}" == "k8s" ]]; then
  die "k8s deployment not yet supported"
fi

# -------- Locate Config File --------
SOURCE_FILE="docker-makefiles/${NODE_CONFIGS}/node_configs.env"
ENV_FILE="docker-makefiles/${NODE_CONFIGS}/formatted_node_configs.env"

[[ -f "${SOURCE_FILE}" ]] || die "Missing configuration file: ${SOURCE_FILE}"

# -------- Generate Snapshot --------
bash docker-makefiles/prep_configs.sh "${NODE_CONFIGS}"

# -------- Load Configs --------
export NETWORK_TYPE=$(grep -m1 '^NETWORK_TYPE=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
export IMAGE=$(grep -m1 '^IMAGE=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
export ENABLE_REMOTE_GUI=$(grep -m1 '^ENABLE_REMOTE_GUI=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')

NODE_NAME=$(grep -m1 '^NODE_NAME=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
CONTAINER_NAME=$(grep -m1 '^CONTAINER_NAME=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
UPDATE_SED="true"

if [[ -n "${CONTAINER_NAME}" ]]; then
  export CONTAINER_NAME
  UPDATE_SED="false"
elif [[ -n "${NODE_NAME}" ]]; then
  export CONTAINER_NAME="${NODE_NAME}"
else
  export CONTAINER_NAME="${NODE_CONFIGS}"
fi

if [[ "${UPDATE_SED}" == "true" ]]; then
  ${SED_INPLACE} "s/^#\{0,1\}CONTAINER_NAME=.*/CONTAINER_NAME=\"${CONTAINER_NAME}\"/g" "${ENV_FILE}"
fi

# Comment out remaining empty-value vars so they are not passed to the container
${SED_INPLACE} -E 's/^([A-Za-z_][A-Za-z0-9_]*)=""(\s*(#.*)?)$/#\1=""\2/' "${ENV_FILE}"

export ANYLOG_SERVER_PORT=$(grep -m1 '^ANYLOG_SERVER_PORT=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
export ANYLOG_REST_PORT=$(grep -m1 '^ANYLOG_REST_PORT=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
export ANYLOG_BROKER_PORT=$(grep -m1 '^ANYLOG_BROKER_PORT=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
export DOCKER_SOCKET=$(grep -m1 '^DOCKER_SOCKET=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
export DEPLOYMENTS_REPO=$(grep -m1 '^DEPLOYMENTS_REPO=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
DEPLOYMENTS_BRANCH="${DEPLOYMENTS_BRANCH:-}"
export USER_VOLUMES=$(grep -m1 '^USER_VOLUMES=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')

# -------- LICENSE_KEY: prefer env var (set by Makefile), fall back to config file --------
if [[ -z "${LICENSE_KEY:-}" ]]; then
  export LICENSE_KEY=$(grep -m1 '^LICENSE_KEY=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
fi

# -------- Select Template --------
COMPOSE_FILE="docker-makefiles/docker-compose-template.yaml"

if [[ -n "${NETWORK_TYPE}" ]] && [[ "${NETWORK_TYPE}" != "network" ]] && [[ "${NETWORK_TYPE}" != "ports" ]]; then
  TEMPLATE_COMPOSE_FILE="docker-makefiles/docker-compose-template-specific-base.yaml"
elif [[ "${NETWORK_TYPE}" == "ports" ]]; then
  TEMPLATE_COMPOSE_FILE="docker-makefiles/docker-compose-template-ports-base.yaml"
elif [[ "${NETWORK_TYPE}" == "network" ]]; then
  TEMPLATE_COMPOSE_FILE="docker-makefiles/docker-compose-template-base.yaml"
elif [[ -z "${NETWORK_TYPE}" ]] && _auto_use_ports_template; then
  TEMPLATE_COMPOSE_FILE="docker-makefiles/docker-compose-template-ports-base.yaml"
else
  TEMPLATE_COMPOSE_FILE="docker-makefiles/docker-compose-template-base.yaml"
fi

[[ -f "$TEMPLATE_COMPOSE_FILE" ]] || die "$TEMPLATE_COMPOSE_FILE not found"
cp "$TEMPLATE_COMPOSE_FILE" "${COMPOSE_FILE}"

# -------- Inject env_file --------
awk -v cfg="../../docker-makefiles/${NODE_CONFIGS}/formatted_node_configs.env" \
    '/    env_file:/ {print; print "      - " cfg; next}1' \
    "${COMPOSE_FILE}" > temp.yaml && mv temp.yaml "${COMPOSE_FILE}"

# -------- Inject Broker Port --------
if [[ "${TEMPLATE_COMPOSE_FILE}" == *"ports"* ]] && [[ "${ANYLOG_BROKER_PORT}" =~ ^[0-9]+$ ]]; then
  awk -v port="${ANYLOG_BROKER_PORT}:${ANYLOG_BROKER_PORT}" \
      '/    ports:/ {print; print "      - " port; next}1' \
      "${COMPOSE_FILE}" > temp.yaml && mv temp.yaml "${COMPOSE_FILE}"
fi

# -------- Remove unresolved placeholders --------
# If ANYLOG_BROKER_PORT is not a valid port number, remove its placeholder
# line from the template so envsubst doesn't produce an invalid "- :" entry.
if [[ ! "${ANYLOG_BROKER_PORT:-}" =~ ^[0-9]+$ ]]; then
  ${SED_INPLACE} '/\${ANYLOG_BROKER_PORT}/d' "${COMPOSE_FILE}"
fi

# -------- Deployment Scripts Volume --------
if [[ -z "${DEPLOYMENTS_REPO}" && -z "${DEPLOYMENTS_BRANCH}" ]] || \
   [[ "${DEPLOYMENTS_REPO}" == "https://github.com/AnyLog-co/deployment-scripts" && "${DEPLOYMENTS_BRANCH}" == "main" ]]; then
  # Option 1: default deployment-scripts built into the image
  echo "Use built-in default option"
  ${SED_INPLACE} "s/#      - \${CONTAINER_NAME}-local-scripts:\/app\/deployment-scripts/      - \${CONTAINER_NAME}-local-scripts:\/app\/deployment-scripts/g" "${COMPOSE_FILE}"
  ${SED_INPLACE} "s/#  \${CONTAINER_NAME}-local-scripts:/  \${CONTAINER_NAME}-local-scripts:/g" "${COMPOSE_FILE}"
elif [[ -n "${DEPLOYMENTS_REPO}" && -d "${DEPLOYMENTS_REPO}" ]]; then
  # Option 2: host directory — update main service, remove from init and volumes
  ${SED_INPLACE} "s|      - \${CONTAINER_NAME}-local-scripts:/app/deployment-scripts|      - ${DEPLOYMENTS_REPO}:/app/deployment-scripts|g" "${COMPOSE_FILE}"
  ${SED_INPLACE} "/^#      - \${CONTAINER_NAME}-local-scripts:\/app\/deployment-scripts/d" "${COMPOSE_FILE}"
  ${SED_INPLACE} "/^#  \${CONTAINER_NAME}-local-scripts:$/d" "${COMPOSE_FILE}"
  awk '/"-init:"/ { in_init=1 } in_init && /deployment-scripts/ { next } /^  [^ ]/ && !/-init:/ { in_init=0 } 1' \
    "${COMPOSE_FILE}" > temp.yaml && mv temp.yaml "${COMPOSE_FILE}"
elif [[ "${DEPLOYMENTS_REPO}" == http://* || "${DEPLOYMENTS_REPO}" == https://* ]]; then
  # Option 3: reclone at startup — no volume needed at all
  ${SED_INPLACE} "/\/app\/deployment-scripts$/d" "${COMPOSE_FILE}"
  ${SED_INPLACE} "/^#  \${CONTAINER_NAME}-local-scripts:$/d" "${COMPOSE_FILE}"
elif [[ -n "${DEPLOYMENTS_REPO}" ]]; then
  # Option 4: secondary deployment-scripts container
  export DEPLOYMENTS_BRANCH=$(grep -m1 '^DEPLOYMENTS_BRANCH=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
  awk -v repo="${DEPLOYMENTS_REPO}" \
      -v branch="${DEPLOYMENTS_BRANCH}" \
      -v node="${CONTAINER_NAME}" '
  /^services:/ {
    print;
    print "  " node "-deployment-scripts:";
    print "    image: " repo ":" branch;
    print "    container_name: " node "-deployment-scripts";
    print "    command: [\"sh\", \"-c\", \"cp -r /app/deployment-scripts/. /volume/\"]";
    print "    restart: \"no\"";
    print "    volumes:";
    print "      - " node "-local-scripts:/app/deployment-scripts";
    next
  }1' "${COMPOSE_FILE}" > temp.yaml && mv temp.yaml "${COMPOSE_FILE}"
  ${SED_INPLACE} "s/condition: service_completed_successfully/condition: service_completed_successfully\n      ${CONTAINER_NAME}-deployment-scripts:\n        condition: service_completed_successfully/g" "${COMPOSE_FILE}"
  ${SED_INPLACE} "s/#      - \${CONTAINER_NAME}-local-scripts:\/app\/deployment-scripts/      - \${CONTAINER_NAME}-local-scripts:\/app\/deployment-scripts/g" "${COMPOSE_FILE}"
  ${SED_INPLACE} "s/#  \${CONTAINER_NAME}-local-scripts:/  \${CONTAINER_NAME}-local-scripts:/g" "${COMPOSE_FILE}"
fi

# -------- Docker Socket --------
if [[ -z "${DOCKER_SOCKET}" ]] || [[ ! -S "${DOCKER_SOCKET}" ]]; then
  ${SED_INPLACE} "s/- \${DOCKER_GID}/#- \${MISSING-DOCKER_GID}/g" "${COMPOSE_FILE}"
  ${SED_INPLACE} "0,/- \${DOCKER_SOCKET}/s#- \${DOCKER_SOCKET}#\# - \${MISSING-DOCKER_SOCKET}#" "${COMPOSE_FILE}"
else
  if stat -c '%g' "${DOCKER_SOCKET}" >/dev/null 2>&1; then
    export DOCKER_GID=$(stat -c '%g' "${DOCKER_SOCKET}")   # GNU stat (Linux)
  else
    export DOCKER_GID=$(stat -f '%g' "${DOCKER_SOCKET}")   # BSD stat (macOS)
  fi
fi

# -------- Host Mounts --------
export HOST_PROC=$(grep -m1 '^HOST_PROC=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
export HOST_ROOT=$(grep -m1 '^HOST_ROOT=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
export HOST_SYS=$(grep -m1  '^HOST_SYS='  "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')

for VAR_NAME in HOST_PROC HOST_ROOT HOST_SYS; do
  HOST_PATH="${!VAR_NAME}"
  if [[ -z "${HOST_PATH}" ]] || [[ ! -e "${HOST_PATH}" ]]; then
    ${SED_INPLACE} "s|- \${${VAR_NAME}}:.*|# - \${MISSING-${VAR_NAME}}|g" "${COMPOSE_FILE}"
  fi
done

# -------- Remote-GUI --------
if [[ "${ENABLE_REMOTE_GUI}" == "true" ]]; then
  export REMOTE_GUI_NIC=$(grep -m1 '^REMOTE_GUI_NIC=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
  export REMOTE_GUI_FE=$(grep -m1 '^REMOTE_GUI_FE=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
  export REMOTE_GUI_BE=$(grep -m1 '^REMOTE_GUI_BE=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
  export REMOTE_GUI_TAG=$(grep -m1 '^REMOTE_GUI_TAG=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
  export GRAFANA_URL=$(grep -m1 '^GRAFANA_URL=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
  export REMOTE_CONN=$(grep -m1 '^REMOTE_CONN=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')
  export OVERLAY_IP=$(grep -m1 '^OVERLAY_IP=' "$ENV_FILE" | cut -d= -f2- | tr -d '"\r')

  REMOTE_GUI_FE="${REMOTE_GUI_FE:-31800}"
  REMOTE_GUI_BE="${REMOTE_GUI_BE:-8080}"
  REMOTE_GUI_TAG="${REMOTE_GUI_TAG:-latest}"

  REMOTE_GUI_IP="127.0.0.1"
  if [[ -n "${REMOTE_GUI_NIC:-}" ]]; then
    if command -v ip >/dev/null 2>&1; then
      REMOTE_GUI_IP=$(ip -4 addr show dev "${REMOTE_GUI_NIC}" | awk '/inet /{print $2}' | cut -d/ -f1)
    elif command -v ifconfig >/dev/null 2>&1; then
      REMOTE_GUI_IP=$(ifconfig "${REMOTE_GUI_NIC}" | awk '/inet /{print $2}')
    fi
  fi

  if [[ ! -n "${REMOTE_CONN:-}" ]] && [[ -n "${OVERLAY_IP}" ]]; then
    export REMOTE_CONN="${OVERLAY_IP}:${ANYLOG_REST_PORT}"
  elif [[ ! -n "${REMOTE_CONN:-}" ]]; then
    export REMOTE_CONN="${REMOTE_GUI_IP}:${ANYLOG_REST_PORT}"
  fi

  awk -v vol1="image-vol:/app/CLI/local-cli-backend/static/" \
      -v vol2="usr-mgm-vol:/app/CLI/local-cli/backend/usr-mgm/" '
/    volumes:/ && !vol_found {
  print; print "      - " vol1; print "      - " vol2; vol_found=1; next
}1
END {
  print "  image-vol:"; print "  usr-mgm-vol:"; print "  report-configs:";
}' "${COMPOSE_FILE}" > temp.yaml && mv temp.yaml "${COMPOSE_FILE}"

  awk -v remote_ip="$REMOTE_GUI_IP" \
      -v grafana="${GRAFANA_URL:-}" \
      -v fe_port="$REMOTE_GUI_FE" \
      -v be_port="$REMOTE_GUI_BE" \
      -v tag="$REMOTE_GUI_TAG" \
      -v remote_conn="${REMOTE_CONN}" '
/services:/ {
  print;
  print "  remote-gui:";
  print "    image: anylogco/remote-gui:" tag;
  print "    container_name: remote-gui";
  print "    hostname: remote-gui";
  print "    restart: always";
  print "    stdin_open: true";
  print "    tty: true";
  print "    ports:";
  print "      - " fe_port ":" fe_port;
  print "      - " be_port ":" be_port;
  print "    environment:";
  print "      - VITE_API_URL=http://" remote_ip ":" be_port;
  print "      - REMOTE_GUI_FE=" fe_port;
  print "      - REMOTE_GUI_BE=" be_port;
  print "      - REMOTE_CONN=" remote_conn;
  if (grafana != "") print "      - GRAFANA_URL=" grafana;
  print "    volumes:";
  print "      - image-vol:/app/CLI/local-cli-backend/static/";
  print "      - usr-mgm-vol:/app/CLI/local-cli/backend/usr-mgm/";
  print "      - report-configs:/app/CLI/local-cli-backend/plugins/reportgenerator/templates";
  next
}1' "${COMPOSE_FILE}" > temp.yaml && mv temp.yaml "${COMPOSE_FILE}"
fi

# -------- USER VOLUMES --------
if [[ -n "${USER_VOLUMES}" ]]; then
  VOLUME_INJECT=""
  for VOLUME in ${USER_VOLUMES}; do
    if [[ "${VOLUME}" == *"/"* ]]; then
      MOUNT_NAME=$(basename "${VOLUME}")
    elif [[ "${VOLUME}" == *"\\"* ]]; then
      MOUNT_NAME=$(echo "${VOLUME}" | awk -F "\\" '{print $NF}')
    else
      MOUNT_NAME="${VOLUME}"
    fi
    VOLUME_INJECT="${VOLUME_INJECT}\n      - ${VOLUME}:/app/${MOUNT_NAME}"
  done
  ${SED_INPLACE} "s#- \${CONTAINER_NAME}-data:/app/AnyLog-Network/data#- \${CONTAINER_NAME}-data:/app/AnyLog-Network/data${VOLUME_INJECT}#g" "${COMPOSE_FILE}"
fi

# -------- Envsubst & Write Output --------
echo "Generating final docker-compose.yaml..."
mkdir -p docker-makefiles/docker-compose-files
OUTPUT_FILE="docker-makefiles/docker-compose-files/${NODE_CONFIGS}-docker-compose.yaml"
envsubst < "${COMPOSE_FILE}" > "$OUTPUT_FILE"
rm -rf "${COMPOSE_FILE}" "${COMPOSE_FILE}.bak" docker-makefiles/${NODE_CONFIGS}/*.bak
echo "Saved: ${OUTPUT_FILE}"
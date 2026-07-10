#!/usr/bin/env bash
# deploy.sh — AnyLog node lifecycle manager
# Usage: bash deploy.sh <command> [OPTIONS]
# Run:   bash deploy.sh help
#setup -euo pipefail

# ──────────────────────────────────────────────
# Defaults  (override via environment or flags)
# ──────────────────────────────────────────────
IS_MANUAL="${IS_MANUAL:-false}"
ANYLOG_TYPE="${ANYLOG_TYPE:-anylog-generic}"
TAG="${TAG:-pre-develop}"
IMAGE="${IMAGE:-anylogco/anylog-network}"
TEST_CONN="${TEST_CONN:-}"
NODE_NAME="${NODE_NAME:-}"
export LICENSE_KEY="${LICENSE_KEY:-}"

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
die() { echo "ERROR: $1" >&2; exit "${2:-1}"; }

# Resolve short-form aliases  (operator → anylog-operator)
_resolve_type() {
  case "$ANYLOG_TYPE" in
    generic|master|operator|query|publisher|standalone-operator|standalone-publisher)
      ANYLOG_TYPE="anylog-${ANYLOG_TYPE}" ;;
  esac
}

# Detect container runtime
_detect_runtime() {
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_CMD="podman"
  else
    CONTAINER_CMD="docker"
  fi

  if command -v podman-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="podman-compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
  else
    DOCKER_COMPOSE_CMD="docker compose"
  fi
}

# Detect platform
_detect_platform() {
  UNAME_M=$(uname -m)
  case "$UNAME_M" in
    x86_64)          DOCKER_PLATFORM="linux/amd64" ;;
    aarch64|arm64)   DOCKER_PLATFORM="linux/arm64" ;;
    *)               die "Unsupported architecture: ${UNAME_M}" ;;
  esac
  export DOCKER_PLATFORM
  export ANYLOG_UID=$(id -u)
  export ANYLOG_GID=$(id -g)
}

# Load IMAGE and NODE_NAME from config files
_load_configs() {
  local env_file="docker-makefiles/${ANYLOG_TYPE}/.env"
  local single_file="docker-makefiles/${ANYLOG_TYPE}/node_configs.env"

  if [[ -f "$env_file" ]]; then
    IMAGE=$(grep -m1 '^IMAGE='     "$env_file"    | cut -d= -f2- | tr -d '"\r')
    NODE_NAME=$(grep -m1 '^NODE_NAME=' "$env_file" | cut -d= -f2- | tr -d '"\r')
  elif [[ -f "$single_file" ]]; then
    IMAGE=$(grep -m1 '^IMAGE='     "$single_file" | cut -d= -f2- | tr -d '"\r')
    NODE_NAME=$(grep -m1 '^NODE_NAME=' "$single_file" | cut -d= -f2- | tr -d '"\r')
  else
    die "Missing configuration file(s) for '${ANYLOG_TYPE}'"
  fi
}

# Resolve TEST_CONN if not set
_resolve_test_conn() {
  if [[ -z "$TEST_CONN" ]]; then
    local single_file="docker-makefiles/${ANYLOG_TYPE}/node_configs.env"
    local rest_port
    rest_port=$(grep -m1 '^ANYLOG_REST_PORT=' "$single_file" 2>/dev/null | cut -d= -f2- | tr -d '"\r' || echo "32549")
    TEST_CONN="127.0.0.1:${rest_port}"
  fi
}

# Validate that ANYLOG_TYPE directory exists
_check_configs() {
  [[ -n "$ANYLOG_TYPE" ]] || die "ANYLOG_TYPE is required"
  [[ -d "docker-makefiles/${ANYLOG_TYPE}" ]] || \
    die "Missing directory 'docker-makefiles/${ANYLOG_TYPE}' — run 'bash deploy.sh help' for valid types"
}

DOCKER_COMPOSE_FILE="docker-makefiles/docker-compose-files/${ANYLOG_TYPE}-docker-compose.yaml"

# remove DOCKER_COMPOSE_FILE if exists
_cmd_clean_compose() {
  if [[ "$IS_MANUAL" == "false" ]] && [[ -f ${DOCKER_COMPOSE_FILE} ]]; then
    rm -rf  "${DOCKER_COMPOSE_FILE}"
  fi
}


# ──────────────────────────────────────────────
# Parse flags  (--is-manual, --type, --tag, etc.)
# ──────────────────────────────────────────────
COMMAND="${1:-help}"
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type|-t)        ANYLOG_TYPE="$2";  shift 2 ;;
    --tag)            TAG="$2";          shift 2 ;;
    --image)          IMAGE="$2";        shift 2 ;;
    --node-name)      NODE_NAME="$2";    shift 2 ;;
    --test-conn)      TEST_CONN="$2";    shift 2 ;;
    --license-key)    export LICENSE_KEY="$2";  shift 2 ;;
    --manual)         IS_MANUAL="true";  shift   ;;
    --no-manual)      IS_MANUAL="false"; shift   ;;
    *) die "Unknown option: $1" ;;
  esac
done

# Apply alias resolution and common setup
_resolve_type
_detect_runtime
_detect_platform
DOCKER_COMPOSE_FILE="docker-makefiles/docker-compose-files/${ANYLOG_TYPE}-docker-compose.yaml"

# ──────────────────────────────────────────────
# Commands
# ──────────────────────────────────────────────

cmd_login() {
  echo "Logging into Docker Hub..."
  ${CONTAINER_CMD} login docker.io -u anyloguser --password-stdin
}

cmd_pull() {
  _check_configs
  _load_configs
  echo "Pulling ${IMAGE}:${TAG}..."
  ${CONTAINER_CMD} pull "docker.io/${IMAGE}:${TAG}"
}

cmd_dry_run() {
  _check_configs
  _load_configs
  if [[ "$IS_MANUAL" == "false" ]]; then
    echo "Dry Run ${ANYLOG_TYPE} - ${NODE_NAME}"
    bash docker-makefiles/prep_configs.sh "${ANYLOG_TYPE}"
    bash docker-makefiles/build_docker_compose.sh "${ANYLOG_TYPE}" "${TAG}"
 elif [[ "${IS_MANUAL}" == "true" ]]; then
    local single_file="docker-makefiles/${ANYLOG_TYPE}/node_configs.env"
    local deployments_repo
    deployments_repo=$(grep -m1 '^DEPLOYMENTS_REPO=' "$single_file" 2>/dev/null | cut -d= -f2- | tr -d '"\r' || true)

    local vol_scripts
    if [[ -n "$deployments_repo" && -d "$deployments_repo" ]]; then
      vol_scripts="-v ${deployments_repo}:/app/deployment-scripts"
    else
      vol_scripts="-v ${NODE_NAME}-local-scripts:/app/deployment-scripts"
    fi

    echo "Manual mode — docker run command:"
    echo ""
    echo "  ${CONTAINER_CMD} run -it -d --detach-keys=ctrl-d \\"
    echo "    --name ${NODE_NAME} \\"
    echo "    --network host \\"
    echo "    --env-file ${single_file} \\"
    echo "    -v ${NODE_NAME}-anylog:/app/AnyLog-Network/anylog \\"
    echo "    -v ${NODE_NAME}-blockchain:/app/AnyLog-Network/blockchain \\"
    echo "    -v ${NODE_NAME}-data:/app/AnyLog-Network/data \\"
    echo "    ${vol_scripts} \\"
    echo "    --restart always \\"
    echo "    ${IMAGE}:${TAG}"
    echo ""
  else
    echo "Dry Run skipped (manual mode)"
    bash docker-makefiles/prep_configs.sh "${ANYLOG_TYPE}"
  fi
}

cmd_up() {
  cmd_dry_run
  if [[ "$IS_MANUAL" == "true" ]]; then
    echo "Deploying ${ANYLOG_TYPE} [manual / docker run]"
    local single_file="docker-makefiles/${ANYLOG_TYPE}/node_configs.env"
    local deployments_repo
    deployments_repo=$(grep -m1 '^DEPLOYMENTS_REPO=' "$single_file" 2>/dev/null | cut -d= -f2- | tr -d '"\r' || true)

    local vol_scripts
    if [[ -n "$deployments_repo" && -d "$deployments_repo" ]]; then
      vol_scripts="-v ${deployments_repo}:/app/deployment-scripts"
    else
      vol_scripts="-v ${NODE_NAME}-local-scripts:/app/deployment-scripts"
    fi

    local license_flag=""
    [[ -n "$LICENSE_KEY" ]] && license_flag="-e LICENSE_KEY=${LICENSE_KEY}"
    ${CONTAINER_CMD} run -it -d --detach-keys=ctrl-d \
      --name "${NODE_NAME}" \
      --network host \
      --env-file "${single_file}" \
      ${license_flag} \
      -v "${NODE_NAME}-anylog:/app/AnyLog-Network/anylog" \
      -v "${NODE_NAME}-blockchain:/app/AnyLog-Network/blockchain" \
      -v "${NODE_NAME}-data:/app/AnyLog-Network/data" \
      ${vol_scripts} \
      --restart always \
      "${IMAGE}:${TAG}"
  else
    echo "Deploying ${ANYLOG_TYPE}"
    LICENSE_KEY="${LICENSE_KEY}" ${DOCKER_COMPOSE_CMD} -f "${DOCKER_COMPOSE_FILE}" up -d
  fi
}

cmd_down() {
  _check_configs
  _load_configs
  if [[ "$IS_MANUAL" == "true" ]]; then
    echo "Stopping ${NODE_NAME} [manual]"
    ${CONTAINER_CMD} stop "${NODE_NAME}" && ${CONTAINER_CMD} rm "${NODE_NAME}"
  else
    cmd_dry_run
    echo "Stopping ${ANYLOG_TYPE}"
    ${DOCKER_COMPOSE_CMD} -f "${DOCKER_COMPOSE_FILE}" down
  fi
}


cmd_clean() {
  _check_configs
  _load_configs
  if [[ "$IS_MANUAL" == "true" ]]; then
    echo "Stopping + removing volumes: ${NODE_NAME} [manual]"
    ${CONTAINER_CMD} stop "${NODE_NAME}" && ${CONTAINER_CMD} rm "${NODE_NAME}"
    ${CONTAINER_CMD} volume rm \
      "${NODE_NAME}-anylog" \
      "${NODE_NAME}-blockchain" \
      "${NODE_NAME}-data" \
      "${NODE_NAME}-local-scripts" 2>/dev/null || true
  else
    cmd_dry_run
    echo "Stopping + removing volumes: ${ANYLOG_TYPE}"
    ${DOCKER_COMPOSE_CMD} -f "${DOCKER_COMPOSE_FILE}" down -v
  fi
  _cmd_clean_compose
}

cmd_clean_all() {
  _check_configs
  _load_configs
  if [[ "$IS_MANUAL" == "true" ]]; then
    echo "Stopping + removing volumes + image: ${NODE_NAME} [manual]"
    ${CONTAINER_CMD} stop "${NODE_NAME}" && ${CONTAINER_CMD} rm "${NODE_NAME}"
    ${CONTAINER_CMD} volume rm \
      "${NODE_NAME}-anylog" \
      "${NODE_NAME}-blockchain" \
      "${NODE_NAME}-data" \
      "${NODE_NAME}-local-scripts" 2>/dev/null || true
    ${CONTAINER_CMD} rmi "${IMAGE}:${TAG}" 2>/dev/null || true
  else
    cmd_dry_run
    echo "Stopping + removing volumes + image: ${ANYLOG_TYPE}"
    ${DOCKER_COMPOSE_CMD} -f "${DOCKER_COMPOSE_FILE}" down -v --rmi all
  fi
  _cmd_clean_compose
}

cmd_logs() {
  _check_configs; _load_configs
  ${CONTAINER_CMD} logs "${NODE_NAME}"
}

cmd_logs_f() {
  _check_configs; _load_configs
  ${CONTAINER_CMD} logs -f "${NODE_NAME}"
}

cmd_attach() {
  _check_configs; _load_configs
  ${CONTAINER_CMD} attach --detach-keys=ctrl-d "${NODE_NAME}"
}

cmd_exec() {
  _check_configs; _load_configs
  ${CONTAINER_CMD} exec -it "${NODE_NAME}" /bin/bash
}

cmd_exec_root() {
  _check_configs; _load_configs
  ${CONTAINER_CMD} exec -u root -it "${NODE_NAME}" /bin/bash
}

# ──────────────────────────────────────────────
# Testing
# ──────────────────────────────────────────────
_curl_anylog() {
  local cmd="$1"
  curl -s -X POST "http://${TEST_CONN}" \
    -H "Content-Type: application/json" \
    -d "{\"command\": \"${cmd}\", \"User-Agent\": \"AnyLog/1.23\"}" \
    -w "\n\n"
}

cmd_test_status() {
  _check_configs; _load_configs; _resolve_test_conn
  echo "Check Status: ${TEST_CONN}"
  _curl_anylog "get status where format=json"
}

cmd_test_node() {
  _check_configs; _load_configs; _resolve_test_conn
  echo "Test Node: ${TEST_CONN}"
  _curl_anylog "test node"
}

cmd_test_network() {
  _check_configs; _load_configs; _resolve_test_conn
  echo "Test Network: ${TEST_CONN}"
  _curl_anylog "test network"
}

cmd_full_test() {
  cmd_test_status
  cmd_test_node
  cmd_test_network
}

cmd_check_processes() {
  _check_configs; _load_configs; _resolve_test_conn
  echo "Active/Inactive Services: ${TEST_CONN}"
  _curl_anylog "get processes"
}

# ──────────────────────────────────────────────
# check-vars / help
# ──────────────────────────────────────────────
cmd_check_vars() {
  _load_configs 2>/dev/null || true
  _resolve_test_conn 2>/dev/null || true
  printf "%-22s %-30s %s\n" "Variable" "Default" "Value"
  printf "%-22s %-30s %s\n" "--------" "-------" "-----"
  printf "%-22s %-30s %s\n" "IS_MANUAL"          "false"                    "$IS_MANUAL"
  printf "%-22s %-30s %s\n" "ANYLOG_TYPE"         "anylog-generic"           "$ANYLOG_TYPE"
  printf "%-22s %-30s %s\n" "IMAGE"               "anylogco/anylog-network"  "$IMAGE"
  printf "%-22s %-30s %s\n" "NODE_NAME"           ""                         "${NODE_NAME:-}"
  printf "%-22s %-30s %s\n" "TAG"                 "pre-develop"              "$TAG"
  printf "%-22s %-30s %s\n" "LICENSE_KEY"         ""                         "${LICENSE_KEY:-}"
  printf "%-22s %-30s %s\n" "TEST_CONN"           "127.0.0.1:<rest-port>"    "$TEST_CONN"
}

cmd_help() {
  cat <<EOF

Usage: bash deploy.sh <command> [OPTIONS]

Commands:
  login                 Log into Docker Hub
  pull                  Pull image from Docker Hub
  dry-run               Generate docker-compose.yaml (skipped in manual mode)
  up                    Start AnyLog instance
  down                  Stop AnyLog instance
  clean                 Stop and remove volumes
  clean-all             Stop, remove volumes and image
  logs                  View container logs
  logs-f                Follow container logs
  attach                Attach to container (ctrl-d to detach)
  exec                  Shell into container (anylog user)
  exec-root             Shell into container (root)
  full-test             Run test-status + test-node + test-network
  test-status           GET status from node
  test-node             Test node configuration
  test-network          Test network connectivity
  check-processes       List active/inactive services
  check-vars            Show resolved variable values
  help                  Show this message

Options:
  --type,  -t <type>    Node type (generic, master, operator, query, publisher,
                        standalone-operator, standalone-publisher)
  --tag       <tag>     Image tag              (default: pre-develop)
  --image     <image>   Image repo             (default: anylogco/anylog-network)
  --node-name <name>    Override container name
  --test-conn <ip:port> REST endpoint for test commands
  --license-key <key>   License key to inject into container env
  --manual              Use docker run instead of docker compose
  --no-manual           Use docker compose (default)

Examples:
  bash deploy.sh up --type operator
  bash deploy.sh up --type operator --manual
  bash deploy.sh down --type anylog-operator
  bash deploy.sh full-test --test-conn 192.168.1.10:32149
  bash deploy.sh exec-root --type master
  bash deploy.sh check-vars --type query

EOF
}

# ──────────────────────────────────────────────
# Dispatch
# ──────────────────────────────────────────────
case "$COMMAND" in
  login)            cmd_login ;;
  pull)             cmd_pull ;;
  dry-run)          cmd_dry_run ;;
  up)               cmd_up ;;
  down)             cmd_down ;;
  clean)            cmd_clean ;;
  clean-all)        cmd_clean_all ;;
  logs)             cmd_logs ;;
  logs-f)           cmd_logs_f ;;
  attach)           cmd_attach ;;
  exec)             cmd_exec ;;
  exec-root)        cmd_exec_root ;;
  full-test)        cmd_full_test ;;
  test-status)      cmd_test_status ;;
  test-node)        cmd_test_node ;;
  test-network)     cmd_test_network ;;
  check-processes)  cmd_check_processes ;;
  check-vars)       cmd_check_vars ;;
  help|--help|-h)   cmd_help ;;
  *)                die "Unknown command '${COMMAND}' — run 'bash deploy.sh help'" ;;
esac
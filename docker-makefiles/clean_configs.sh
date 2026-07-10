#!/usr/bin/env bash

# -------- Helpers --------
die() {
  echo "Error: $1" >&2
  exit "${2:-1}"
}

# -------- Args --------
NODE_CONFIGS=${1:-anylog-generic}

# -------- Locate Config File --------
SOURCE_FILE="docker-makefiles/${NODE_CONFIGS}/node_configs.env"
[[ -f "${SOURCE_FILE}" ]] || die "Missing configuration file: ${SOURCE_FILE}"

SNAPSHOT_FILE="docker-makefiles/${NODE_CONFIGS}/formatted_node_configs.env"
DOCKER_DIR="docker-makefiles/docker-compose-files"
DOCKER_FILE="${DOCKER_DIR}/${NODE_CONFIGS}-docker-compose.yaml"
NODE_NAME_FILE="docker-makefiles/${NODE_CONFIGS}/NODE_NAME.txt"

# -------- Remove files --------
printf "Warning: this will fully reset this node's deployment configuration.\nThe node will be treated as new on next startup and assigned a new identity.\nProceed? [y/N]: "
read -r CONFIRM_DELETE

if [[ "${CONFIRM_DELETE}" == "y" || "${CONFIRM_DELETE}" == "Y" ]]; then
  rm -rf "${DOCKER_FILE}" "${SNAPSHOT_FILE}" "${NODE_NAME_FILE}"
  if [[ -d "${DOCKER_DIR}" && -z "$(ls -A "${DOCKER_DIR}")" ]]; then
    rm -rf "${DOCKER_DIR}"
  fi
else
  echo "Deletion cancelled."
fi
#!/usr/bin/env bash

# -------- Helpers --------
die() {
  echo "Error: $1" >&2
  exit "${2:-1}"
}

sedi() {
  local expr="$1"
  shift
  if [ "$#" -eq 0 ]; then
    echo "sedi: no files provided" >&2
    return 1
  fi
  if sed --version >/dev/null 2>&1; then
    sed -i "$expr" "$@"
  else
    sed -i '' "$expr" "$@"
  fi
}

# -------- Args --------
NODE_CONFIGS=${1:-anylog-generic}

# -------- Locate Config File --------
SOURCE_FILE="docker-makefiles/${NODE_CONFIGS}/node_configs.env"
SNAPSHOT_FILE="docker-makefiles/${NODE_CONFIGS}/formatted_node_configs.env"

[[ -f "${SOURCE_FILE}" ]] || die "Missing configuration file: ${SOURCE_FILE}"

# -------- Step 1: Copy node_configs.env -> formatted_node_configs.env --------
# node_configs.env is never modified — all transformations happen on the snapshot only.
[[ -f "${SNAPSHOT_FILE}" ]] && rm -f "${SNAPSHOT_FILE}"
echo "Generating snapshot: ${SNAPSHOT_FILE}"
cp "${SOURCE_FILE}" "${SNAPSHOT_FILE}"

# -------- Step 2: Fix quotation issues in snapshot --------
# Transforms:  MY_VAR='XXX'  ->  MY_VAR="XXX"
# Leaves already-double-quoted, unquoted, and comment lines untouched.
sedi "s/=''/=\"\"/g" "${SNAPSHOT_FILE}"
sedi -E "s/^([A-Za-z_][A-Za-z0-9_]*)='(.*)'/\1=\"\2\"/" "${SNAPSHOT_FILE}"

# -------- Step 3: Normalize LICENSE_KEY in snapshot --------
# Strip surrounding quotes, replace internal single quotes with double quotes.
CURRENT_LICENSE_KEY=$(sed -n 's/^LICENSE_KEY=//p' "${SOURCE_FILE}")
CURRENT_LICENSE_KEY="${CURRENT_LICENSE_KEY%$'\r'}"
CURRENT_LICENSE_KEY="${CURRENT_LICENSE_KEY#\"}" ; CURRENT_LICENSE_KEY="${CURRENT_LICENSE_KEY%\"}"
CURRENT_LICENSE_KEY="${CURRENT_LICENSE_KEY#\'}" ; CURRENT_LICENSE_KEY="${CURRENT_LICENSE_KEY%\'}"

if [[ -z "${CURRENT_LICENSE_KEY}" ]]; then
  echo "No LICENSE_KEY found in ${SOURCE_FILE} — skipping"
else
  UPDATED_LICENSE_KEY="${CURRENT_LICENSE_KEY//\'/\"}"
  sedi "s|^LICENSE_KEY=.*|LICENSE_KEY=${UPDATED_LICENSE_KEY}|" "${SNAPSHOT_FILE}"
  echo "LICENSE_KEY updated in snapshot"
fi

# -------- Step 4: Set permissions --------
# 644: owner-writable so build_docker_compose.sh can resolve and write vars (e.g. CONTAINER_NAME);
# group/other read-only so it's not accidentally hand-edited.
chmod 644 "${SNAPSHOT_FILE}"

echo "Config update complete."
#!/usr/bin/env bash
# =============================================================================
# env2json.sh
#
# Converts a .env file into JSON config files, mirroring the Python
# implementation (env2json.py).
#
# Reads:
#   INPUT_DIR/node_configs.env
#   ROOT_DIR/service.definition.json
#   ROOT_DIR/service.policy.json
#   ROOT_DIR/node.policy.json
#   ROOT_DIR/service.deployment.json
#
# Writes:
#   INPUT_DIR/service.definition.json  — userInput replaced, image tag set
#   INPUT_DIR/service.policy.json      — constraints set to node_name
#   INPUT_DIR/node.policy.json         — purpose property set to node_name
#   INPUT_DIR/service.deployment.json  — userInput.inputs built from env vars,
#                                        constraints set to node_name
#
# Type casting rules (mirrors ast.literal_eval):
#   - Pure integer or float → JSON number, type "int"
#   - Everything else       → JSON string, type "string"
#   - true/false stay as    → type "string" (Python needs True/False)
#
# Requires: jq
#
# Usage:
#   ./env2json.sh [INPUT_DIR] [ROOT_DIR] [TAG]
#
# Defaults:
#   INPUT_DIR = anylog-generic
#   ROOT_DIR  = ./
#   TAG       = pre-develop
# =============================================================================

set -euo pipefail

INPUT_DIR="${1:-anylog-generic}"
ROOT_DIR="${2:-.}"
TAG="${3:-pre-develop}"

# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #
if [[ ! -d "${INPUT_DIR}" ]]; then
    echo "Unable to find directory: ${INPUT_DIR}" >&2
    exit 1
elif [[ ! -f "${INPUT_DIR}/node_configs.env" ]]; then
    echo "Unable to find config file: ${INPUT_DIR}/node_configs.env" >&2
    exit 1
fi

for src_file in \
    "${ROOT_DIR}/service.definition.json" \
    "${ROOT_DIR}/service.policy.json" \
    "${ROOT_DIR}/node.policy.json" \
    "${ROOT_DIR}/service.deployment.json"; do
    if [[ ! -f "${src_file}" ]]; then
        echo "Missing base config file: ${src_file}" >&2
        exit 1
    fi
done

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed." >&2
    exit 1
fi

INPUT_ENV="${INPUT_DIR}/node_configs.env"
OUTPUT_SERVICE_DEFINITION="${INPUT_DIR}/service.definition.json"
OUTPUT_SERVICE_POLICY="${INPUT_DIR}/service.policy.json"
OUTPUT_NODE_POLICY="${INPUT_DIR}/node.policy.json"
OUTPUT_SERVICE_DEPLOYMENT="${INPUT_DIR}/service.deployment.json"

# --------------------------------------------------------------------------- #
# Helper – emit one userInput entry into the accumulator file
# --------------------------------------------------------------------------- #
emit_entry() {
    local param="$1"
    local comment="$2"
    local raw_value="$3"
    local accum_file="$4"

    # Strip surrounding double-quotes, then trim whitespace
    local value="$raw_value"
    if [[ ${#value} -ge 2 && "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
        value="${value:1:${#value}-2}"
    fi
    value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Build label: remove '#' chars and trim
    local label
    label="$(printf '%s' "$comment" | sed 's/#//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # Type-cast (mirrors ast.literal_eval)
    local vtype="string"
    if [[ "$value" =~ ^-?[0-9]+$ ]] || [[ "$value" =~ ^-?[0-9]*\.[0-9]+$ ]]; then
        vtype="int"
    fi

    local tmp
    tmp="$(mktemp)"

    if [[ "$vtype" == "int" ]]; then
        jq --arg  name  "$param"  \
           --arg  label "$label"  \
           --arg  type  "$vtype"  \
           --argjson value "$value" \
           '. += [{"name": $name, "label": $label, "type": $type, "value": $value}]' \
           "$accum_file" > "$tmp"
    else
        jq --arg name  "$param"  \
           --arg label "$label"  \
           --arg type  "$vtype"  \
           --arg value "$value"  \
           '. += [{"name": $name, "label": $label, "type": $type, "value": $value}]' \
           "$accum_file" > "$tmp"
    fi

    mv "$tmp" "$accum_file"
}

# --------------------------------------------------------------------------- #
# Parse .env → build userInput array, capture NODE_NAME and IMAGE
# --------------------------------------------------------------------------- #
ACCUM="$(mktemp)"
echo "[]" > "$ACCUM"

comment=""
param=""
value=""
node_name=""
image=""

while IFS= read -r line || [[ -n "$line" ]]; do

    line="${line%$'\r'}"

    if [[ -n "${line// /}" ]]; then
        if [[ "$line" == \#===* || "$line" == \#---* ]]; then
            :
        elif [[ "$line" == \#* ]]; then
            local_stripped="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            comment+="${local_stripped}"
        elif [[ "$line" == *=* ]]; then
            param="${line%%=*}"
            value="${line#*=}"
        fi
    fi

    if [[ -n "$comment" && -n "$param" && -n "$value" ]]; then

        if [[ "$param" == "NODE_NAME" && -z "$node_name" ]]; then
            raw="${value%$'\r'}"
            raw="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            if [[ ${#raw} -ge 2 && "${raw:0:1}" == '"' && "${raw: -1}" == '"' ]]; then
                raw="${raw:1:${#raw}-2}"
            fi
            [[ -n "$raw" ]] && node_name="$raw"
        elif [[ "$param" == "IMAGE" && -z "$image" ]]; then
            raw="${value%$'\r'}"
            raw="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            if [[ ${#raw} -ge 2 && "${raw:0:1}" == '"' && "${raw: -1}" == '"' ]]; then
                raw="${raw:1:${#raw}-2}"
            fi
            [[ -n "$raw" ]] && image="$raw"
        fi

        emit_entry "$param" "$comment" "$value" "$ACCUM"
        comment=""
        param=""
        value=""
    fi

done < "$INPUT_ENV"

[[ -z "$image"     ]] && image="anylogco/anylog-network"
[[ -z "$node_name" ]] && node_name="anylog-node"

# --------------------------------------------------------------------------- #
# 1. Update service.definition.json — inject userInput and set image
# --------------------------------------------------------------------------- #
user_input_json="$(cat "$ACCUM")"
rm -f "$ACCUM"

tmp="$(mktemp)"
jq --argjson ui "$user_input_json" \
   --arg image "${image}:${TAG}" \
   '.userInput = $ui | .deployment.services["$SERVICE_NAME"].image = $image' \
   "${ROOT_DIR}/service.definition.json" > "$tmp"
cp "$tmp" "$OUTPUT_SERVICE_DEFINITION"
jq --arg node_name "$node_name" \
   '.deployment.services["$SERVICE_NAME"].binds = [
      ($node_name + "-anylog:/app/AnyLog-Network/anylog"),
      ($node_name + "-blockchain:/app/AnyLog-Network/blockchain"),
      ($node_name + "-data:/app/AnyLog-Network/data")
   ]' \
   "$OUTPUT_SERVICE_DEFINITION" > "$tmp"
cp "$tmp" "$OUTPUT_SERVICE_DEFINITION"


echo "✓  service.definition.json → '${OUTPUT_SERVICE_DEFINITION}'"

# --------------------------------------------------------------------------- #
# 2. Update service.policy.json — set constraints
# --------------------------------------------------------------------------- #
tmp="$(mktemp)"
jq --arg node_name "$node_name" \
   '.constraints = ["openhorizon.allowPrivileged == true AND purpose == \($node_name)"]' \
   "${ROOT_DIR}/service.policy.json" > "$tmp"
cp "$tmp" "$OUTPUT_SERVICE_POLICY"
echo "✓  service.policy.json     → '${OUTPUT_SERVICE_POLICY}'"

# --------------------------------------------------------------------------- #
# 3. Update node.policy.json — set purpose property value
# --------------------------------------------------------------------------- #
tmp="$(mktemp)"
jq --arg node_name "$node_name" '
    if .properties != null then
        .properties = [
            .properties[] |
            if .name == "purpose" then .value = $node_name
            else .
            end
        ]
    else .
    end' \
    "${ROOT_DIR}/node.policy.json" > "$tmp"
cp "$tmp" "$OUTPUT_NODE_POLICY"
echo "✓  node.policy.json        → '${OUTPUT_NODE_POLICY}'"

# --------------------------------------------------------------------------- #
# 4. Update service.deployment.json — build inputs from service.definition.json
#    userInput entries, wrap in deployment policy envelope, set constraints,
#    and sync serviceVersions[0].version from service.definition.json
# --------------------------------------------------------------------------- #

# --------------------------------------------------------------------------- #
# 4. Update service.deployment.json — build inputs from service.definition.json
#    userInput entries, wrap in deployment policy envelope, set constraints,
#    and sync serviceVersions[0].version from service.definition.json
# --------------------------------------------------------------------------- #
svc_def_version="$(jq -r '.version // empty' "${ROOT_DIR}/service.definition.json")"

tmp="$(mktemp)"
jq --argjson inputs "$user_input_json" \
   --arg node_name "$node_name" \
   --arg version "${svc_def_version:-}" \
   '
   .constraints = ["purpose == \($node_name)", "openhorizon.allowPrivileged == true"] |
   .userInput[0].inputs = $inputs |
   if $version != "" then
       .service.serviceVersions[0].version = $version
   else . end
   ' \
   "${ROOT_DIR}/service.deployment.json" > "$tmp"
cp "$tmp" "$OUTPUT_SERVICE_DEPLOYMENT"
rm -f "$tmp"
echo "✓  service.deployment.json → '${OUTPUT_SERVICE_DEPLOYMENT}'"

#!/usr/bin/env bash
# license_key.sh — license acceptance form and registration
#
# Usage:
#   bash license-generator/license_key.sh [LICENSE_KEY]
#
# If LICENSE_KEY is provided as $1, skips the key prompt.
# If not provided, prompts the user to enter it.
#
# Environment:
#   LICENSE_URL   License server endpoint (default: http://23.239.12.151:8001/api/license-accept)
#set -euo pipefail

LICENSE_KEY="${1:-}"
LICENSE_URL="${LICENSE_URL:-http://23.239.12.151:8001/api/license-accept}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Skip if already accepted and no new key/prompt was requested ──────
if [[ -f ".license_accepted" && -z "${LICENSE_KEY}" && "${FORCE_LICENSE_PROMPT:-false}" != "true" ]]; then
  exit 0
fi

# ── Smart quote helpers ───────────────────────────────────────────────
_LQ=$(printf '\342\200\234')
_RQ=$(printf '\342\200\235')

# ── Validate license key format ───────────────────────────────────────
_validate_key() {
  local key="$1"
  echo "${key}" | awk -v lq="${_LQ}" -v rq="${_RQ}" '{
    brace = index($0, "{")
    if (brace == 0) { print "INVALID|no brace in key"; exit }
    hex  = substr($0, 1, brace - 1)
    json = substr($0, brace)
    gsub(/\\"/, "\"", json); gsub(lq, "\"", json); gsub(rq, "\"", json)
    hex_ok = (length(hex) == 256 && hex ~ /^[0-9a-fA-F]+$/)
    co_ok  = (json ~ /"company"[ \t]*:[ \t]*"[^"]+"/  )
    ex_ok  = (json ~ /"expiration"[ \t]*:[ \t]*"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"/)
    ty_ok  = (json ~ /"type"[ \t]*:[ \t]*"[^"]+"/     )
    if (hex_ok && co_ok && ex_ok && ty_ok) { print "VALID"; exit }
    msg = "INVALID|"
    if (!hex_ok) msg = msg "hex must be 256 hex chars (got " length(hex) "); "
    if (!co_ok)  msg = msg "missing/invalid company; "
    if (!ex_ok)  msg = msg "missing/invalid expiration YYYY-MM-DD; "
    if (!ty_ok)  msg = msg "missing/invalid type; "
    print msg; exit
  }'
}

# ── Parse field from license key JSON ────────────────────────────────
# Extracts the value of a named field from the JSON suffix of the key.
# Uses index-based substr to avoid greedy-match issues with gsub.
_parse_key() {
  local field="$1" key="$2"
  echo "${key}" | awk -v lq="${_LQ}" -v rq="${_RQ}" -v field="${field}" '{
    brace = index($0, "{")
    if (brace == 0) { print ""; exit }
    json = substr($0, brace)
    gsub(/\\"/, "\"", json); gsub(lq, "\"", json); gsub(rq, "\"", json)
    # Build search needle: "field", then tolerate normal JSON spacing around the colon.
    needle = "\"" field "\""
    pos = index(json, needle)
    if (pos == 0) { print ""; exit }
    rest = substr(json, pos + length(needle))
    colon = index(rest, ":")
    if (colon == 0) { print ""; exit }
    rest = substr(rest, colon + 1)
    sub(/^[ \t]*/, "", rest)
    if (substr(rest, 1, 1) != "\"") { print ""; exit }
    rest = substr(rest, 2)
    # Value ends at the first unescaped double-quote
    end_pos = index(rest, "\"")
    if (end_pos == 0) { print ""; exit }
    print substr(rest, 1, end_pos - 1)
  }'
}

# ── Show license agreement ────────────────────────────────────────────
if [[ -f "${SCRIPT_DIR}/../LICENSE.txt" ]]; then
  more "${SCRIPT_DIR}/../LICENSE.txt"
fi

echo ""
echo "========================================"
echo "  License Agreement Acceptance Required"
echo "========================================"
echo ""


# ── Prompt for license key if needed ──────────────────────────────────
while true; do
  if [[ -z "${LICENSE_KEY}" ]]; then
    printf "License Key:  "; read -r LICENSE_KEY </dev/tty
  fi

  LICENSE_KEY=$(echo "${LICENSE_KEY}" | awk -v lq="${_LQ}" -v rq="${_RQ}" \
    '{gsub(/\\"/, "\""); gsub(lq, "\""); gsub(rq, "\""); print}')
  _RESULT=$(_validate_key "${LICENSE_KEY}")
  if [[ "${_RESULT}" == "VALID" ]]; then
    break
  fi

  echo "  ERROR: Invalid license key - $(echo "${_RESULT}" | cut -d'|' -f2)"
  if [[ ! -t 0 && ! -r /dev/tty ]]; then
    exit 1
  fi
  LICENSE_KEY=""
done

# ── Extract info from key ─────────────────────────────────────────────
COMPANY=$(_parse_key "company"    "${LICENSE_KEY}")
TYPE=$(_parse_key "type"          "${LICENSE_KEY}")
EXPIRATION=$(_parse_key "expiration" "${LICENSE_KEY}")

echo ""
echo "License key recognized:"
echo "  Company:    ${COMPANY}"
echo "  Type:       ${TYPE}"
echo "  Expires:    ${EXPIRATION}"
echo ""

# ── Detect interactive TTY ────────────────────────────────────────────
_tty_available() { [[ -t 0 ]] || { exec 3</dev/tty; } 2>/dev/null; }
if ! _tty_available 2>/dev/null; then
  NAME="Unknown"
  EMAIL="Unknown"
  PROJECT="Unknown"
else
  # ── Collect user info ───────────────────────────────────────────────
  while true; do
    printf "Full Name:    "; read -r NAME </dev/tty
    echo "${NAME}" | grep -qE '^[A-Za-z]{2,}( [A-Za-z]+)+$' && break
    echo "  ERROR: Please enter a valid full name (first and last name, letters only)."
  done

  while true; do
    printf "Email:        "; read -r EMAIL </dev/tty
    echo "${EMAIL}" | grep -qE '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$' && break
    echo "  ERROR: Please enter a valid email address (e.g. user@example.com)."
  done

  while true; do
    printf "Project:      "; read -r PROJECT </dev/tty
    [[ $(echo "${PROJECT}" | tr -d '[:space:]' | wc -c) -ge 2 ]] && break
    echo "  ERROR: Project name must be at least 2 characters."
  done
fi

NAME="${NAME:-Unknown}"
EMAIL="${EMAIL:-Unknown}"
PROJECT="${PROJECT:-Unknown}"

# ── Final acceptance confirmation ─────────────────────────────────────
echo ""
while true; do
  printf "Do you accept the license agreement? [yes/no]: "; read -r ANSWER </dev/tty
  case "${ANSWER}" in
    yes|no) break ;;
    *) echo "  ERROR: Please type 'yes' or 'no'." ;;
  esac
done

echo ""
if [[ "${ANSWER}" != "yes" ]]; then
  echo "License not accepted. Aborting."
  exit 1
fi

# ── POST to license server ────────────────────────────────────────────
echo "Registering license acceptance..."
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 -c "
import json, sys
print(json.dumps({
  'name':        sys.argv[1],
  'company':     sys.argv[2],
  'email':       sys.argv[3],
  'project':     sys.argv[4],
  'license_key': sys.argv[5],
  'timestamp':   sys.argv[6]
}))
" "${NAME}" "${COMPANY}" "${EMAIL}" "${PROJECT}" "${LICENSE_KEY}" "${TS}" > /tmp/license_payload.json

HTTP_CODE=$(curl -sk -o /tmp/license_response.txt -w "%{http_code}" \
  -X POST "${LICENSE_URL}" \
  -H "Content-Type: application/json" \
  -d @/tmp/license_payload.json) || true

if [[ "${HTTP_CODE}" == "200" ]] || [[ "${HTTP_CODE}" == "201" ]]; then
  echo "Registration successful."
  echo "${NAME}|${COMPANY}|${EMAIL}|${PROJECT}|${LICENSE_KEY}|${TS}" > .license_accepted
else
  echo "We could not complete license registration right now."
  echo "Please contact support@anylog.co with your license information."
  printf "Continue anyway? [yes/no]: "; read -r CONT </dev/tty
  if [[ "${CONT}" != "yes" ]]; then
    echo "Aborting."
    exit 1
  fi
  echo "${NAME}|${COMPANY}|${EMAIL}|${PROJECT}|${LICENSE_KEY}|${TS}|unregistered" > .license_accepted
fi
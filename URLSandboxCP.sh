#!/usr/bin/env bash
#
# cp-url-rep.sh — Check a URL's Sandbox using Check Point's Sandbox Service API.
# Ref: https://github.com/CheckPointSW/reputation-service-api
#
# Usage:
#   export CP_REP_API_KEY="your-api-key"      # get one at TCAPI_SUPPORT@checkpoint.com
#   ./cp-url-rep.sh https://example.com
#   ./cp-url-rep.sh --raw https://example.com   # print full JSON response
#
# The auth token is valid ~1 week and is cached under ~/.cache so it is
# reused across runs instead of being regenerated on every call.

set -euo pipefail

# --- Endpoints -------------------------------------------------------------
AUTH_URL="https://rep.checkpoint.com/rep-auth/service/v1.0/request"
QUERY_URL="https://rep.checkpoint.com/url-rep/service/v3.0/query"

# --- Token cache -----------------------------------------------------------
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cp-rep"
TOKEN_FILE="$CACHE_DIR/token"

# --- Helpers ---------------------------------------------------------------
die() { echo "Error: $*" >&2; exit 1; }

have_jq() { command -v jq >/dev/null 2>&1; }

# Percent-encode a string for safe use in a query parameter.
urlencode() {
  if have_jq; then
    jq -r -n --arg s "$1" '$s|@uri'
  else
    local s="$1" out="" c i
    for ((i = 0; i < ${#s}; i++)); do
      c="${s:i:1}"
      case "$c" in
        [a-zA-Z0-9.~_-]) out+="$c" ;;
        *) printf -v c '%%%02X' "'$c"; out+="$c" ;;
      esac
    done
    printf '%s' "$out"
  fi
}

# The token looks like: exp=1578566241~acl=/*~hmac=...
# Pull the epoch from exp= so we know when it expires.
token_expiry() {
  local tok="$1"
  [[ "$tok" =~ exp=([0-9]+) ]] && echo "${BASH_REMATCH[1]}" || echo 0
}

# Fetch a fresh token from the rep-auth service and cache it.
fetch_token() {
  local resp
  resp="$(curl_cli -k -fsSL "$AUTH_URL" -H "Client-Key: $CP_REP_API_KEY")" \
    || die "Failed to obtain auth token (check your API key / quota)."
  [[ -n "$resp" ]] || die "rep-auth returned an empty token."
  mkdir -p "$CACHE_DIR"
  printf '%s' "$resp" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  printf '%s' "$resp"
}

# Return a valid token, refreshing it if missing or within 1 day of expiry.
get_token() {
  if [[ -f "$TOKEN_FILE" ]]; then
    local tok exp now
    tok="$(cat "$TOKEN_FILE")"
    exp="$(token_expiry "$tok")"
    now="$(date +%s)"
    if (( exp > now + 86400 )); then
      printf '%s' "$tok"
      return
    fi
  fi
  fetch_token
}

# --- Argument parsing ------------------------------------------------------
RAW=0
URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw) RAW=1; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) die "Unknown option: $1" ;;
    *) URL="$1"; shift ;;
  esac
done

[[ -n "${CP_REP_API_KEY:-}" ]] || die "CP_REP_API_KEY is not set."
[[ -n "$URL" ]] || die "No URL given. Usage: $0 [--raw] <url>"

# --- Query -----------------------------------------------------------------
TOKEN="$(get_token)"
ENCODED="$(urlencode "$URL")"
BODY="$(printf '{"request":[{"resource":"%s"}]}' "$URL")"

RESPONSE="$(
  curl_cli -k -fsSL -X POST "${QUERY_URL}?resource=${ENCODED}" \
    -H "Client-Key: $CP_REP_API_KEY" \
    -H "token: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$BODY"
)" || die "Sandbox query failed."

# --- Output ----------------------------------------------------------------
if [[ "$RAW" -eq 1 ]] || ! have_jq; then
  echo "$RESPONSE"
else
  echo "$RESPONSE" | jq -r '
    .[0] // .response[0] // . |
    "URL:            \(.resource // "n/a")
Classification: \(.reputation.classification // "n/a")
Severity:       \(.reputation.severity // "n/a")
Confidence:     \(.reputation.confidence // "n/a")
Risk:           \(.risk // .reputation.risk // "n/a")"
  '
fi

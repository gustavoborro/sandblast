#!/usr/bin/env bash
set -euo pipefail

show_help() {
cat <<EOF

Check Point Threat Prevention API Test Script

Usage:
  ./tpapi_test.sh -g <gateway_ip> -f <file> [-p poll_seconds] [-m max_attempts]

Required:
  -g    Gateway IP or hostname
  -f    File to upload

Optional:
  -p    Poll interval in seconds (default: 5)
  -m    Max polling attempts (default: 24)
  -h    Show this help

Examples:
  ./tpapi_test.sh -g 192.168.2.110 -f test.docx
  ./tpapi_test.sh -g 192.168.2.110 -f test.pdf -p 10 -m 60

EOF
}

# Defaults for optional params only
POLL_SECONDS=5
MAX_ATTEMPTS=24

# Parse args
GATEWAY=""
FILE=""

while getopts ":g:f:p:m:h" opt; do
  case $opt in
    g) GATEWAY="$OPTARG" ;;
    f) FILE="$OPTARG" ;;
    p) POLL_SECONDS="$OPTARG" ;;
    m) MAX_ATTEMPTS="$OPTARG" ;;
    h) show_help; exit 0 ;;
    \?) echo "Invalid option: -$OPTARG"; show_help; exit 1 ;;
  esac
done

# Validate required args
if [[ -z "$GATEWAY" || -z "$FILE" ]]; then
  echo "ERROR: -g (gateway) and -f (file) are required"
  show_help
  exit 1
fi

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: File not found: $FILE"
  exit 1
fi

FILENAME=$(basename "$FILE")

UPLOAD_URL="https://${GATEWAY}:18194/tecloud/api/v1/file/upload"
QUERY_URL="https://${GATEWAY}:18194/tecloud/api/v1/file/query"

echo
echo "Uploading file..."
echo "Gateway : $GATEWAY"
echo "File    : $FILE"
echo

UPLOAD_RESPONSE=$(curl_cli --noproxy "$GATEWAY" -k -sS \
  -X POST "$UPLOAD_URL" \
  -F "request={\"request\":{\"file_name\":\"$FILENAME\",\"features\":[\"te\"]}};type=application/json" \
  -F "file=@$FILE")

UPLOAD_STATUS=$(echo "$UPLOAD_RESPONSE" | jq -r '.response.status.label // .response[0].status.label')

if [[ "$UPLOAD_STATUS" != "UPLOAD_SUCCESS" ]]; then
  echo "Upload failed:"
  echo "$UPLOAD_RESPONSE" | jq
  exit 1
fi

SHA1=$(echo "$UPLOAD_RESPONSE" | jq -r '.response.sha1')

echo "Upload status : $UPLOAD_STATUS"
echo "SHA1          : $SHA1"
echo

echo "Polling for result..."

for ((i=1; i<=MAX_ATTEMPTS; i++)); do

  QUERY_RESPONSE=$(curl_cli --noproxy "$GATEWAY" -k -sS \
    -X POST "$QUERY_URL" \
    -H "Content-Type: application/json" \
    -d "{\"request\":{\"sha1\":\"$SHA1\",\"file_name\":\"$FILENAME\",\"features\":[\"te\"]}}")

  VERDICT=$(echo "$QUERY_RESPONSE" | jq -r '.response.te.combined_verdict // empty')

  if [[ -n "$VERDICT" ]]; then
    echo
    echo "=============================="
    echo " Threat Prevention API Result"
    echo "=============================="
    echo "File             : $FILENAME"
    echo "SHA1             : $SHA1"
    echo "Main status      : $(echo "$QUERY_RESPONSE" | jq -r '.response.status.label')"
    echo "TE status        : $(echo "$QUERY_RESPONSE" | jq -r '.response.te.status.label')"
    echo "Combined verdict : $VERDICT"
    echo "Confidence       : $(echo "$QUERY_RESPONSE" | jq -r '.response.te.confidence')"
    echo "Severity         : $(echo "$QUERY_RESPONSE" | jq -r '.response.te.severity')"
    echo
    echo "Sandbox images:"
    echo "$QUERY_RESPONSE" | jq -r '
      .response.te.images[]? |
      "  - ID: \(.id)\n    Status: \(.status)\n    Verdict: \(.report.verdict)"
    '
    exit 0
  fi

  echo "Attempt $i/$MAX_ATTEMPTS - result not ready yet..."
  sleep "$POLL_SECONDS"
done

echo
echo "Timed out waiting for result."
echo "Last response:"
echo "$QUERY_RESPONSE" | jq
exit 2

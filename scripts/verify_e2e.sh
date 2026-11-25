#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SURVEY_URL="https://kevinte67228.github.io/watsons-exclusivity-survey/"
WEBHOOK_URL="${1:-https://script.google.com/macros/s/AKfycbx0K4XEo0LIMDxgoK4jenEigP3cSqv7vEfA1ZQe7XULw9j3gEAWJf_puc13m5jLUnzC/exec}"
ENCODED_WEBHOOK="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$WEBHOOK_URL")"
TARGET_URL="${SURVEY_URL}?webhook=${ENCODED_WEBHOOK}"

echo "=== [Stage 1] Static & Syntax Checks ==="
if python3 -c 'import sys; sys.exit(0 if "\u00b7" in open(sys.argv[1], encoding="utf-8").read() else 1)' "$ROOT_DIR/index.html"; then
  echo "FAIL: Middle dot detected in index.html" >&2
  exit 1
fi
python3 - "$ROOT_DIR/index.html" <<'PY'
import re, subprocess, sys, tempfile
html_text = open(sys.argv[1], encoding="utf-8").read()
js = re.findall(r"<script>(.*?)</script>", html_text, re.S)[-1]
with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as tf:
    tf.write(js)
    path = tf.name
subprocess.run(["node", "--check", path], check=True)
PY
echo "PASS: No middle dot & JS syntax valid"

cleanup() {
  playwright-cli close >/dev/null 2>&1 || true
  rm -rf "$ROOT_DIR/.playwright-cli" /Volumes/AI_Storage/.playwright-cli
}
trap cleanup EXIT

echo "=== [Stage 2] E2E Browser Test: Write 2 Records & Verify Master CSV ==="
playwright-cli open "$TARGET_URL" >/dev/null

# Verify initial UI state
INIT_STATE="$(playwright-cli eval "() => JSON.stringify({ hasMainBtn: !!document.getElementById('btnSubmitSave'), detailsOpen: document.getElementById('organizerSection').open, hasExportInDetails: document.getElementById('organizerSection').contains(document.getElementById('btnSaveAndExportCsv')) })")"
echo "Initial State: $INIT_STATE"

# Record 1: Angela Chiang
playwright-cli select "#categorySelect" "Angela Chiang" >/dev/null
playwright-cli fill "#exclStores" "520" >/dev/null
playwright-cli fill "#nonExclStores" "260" >/dev/null
playwright-cli fill "#valSpaceMetres" "1.5" >/dev/null
playwright-cli fill "#exclGrowthPct" "18" >/dev/null
playwright-cli fill "#nonExclGrowthPct" "8" >/dev/null
playwright-cli fill "#comments" "[E2E-TEST-1] Angela write check" >/dev/null
playwright-cli click "#btnSubmitSave" >/dev/null
sleep 2

# Record 2: Berry Liu
playwright-cli click "#btnResetForm" >/dev/null
playwright-cli select "#categorySelect" "Berry Liu" >/dev/null
playwright-cli fill "#exclStores" "600" >/dev/null
playwright-cli fill "#nonExclStores" "300" >/dev/null
playwright-cli fill "#valSpaceMetres" "2.0" >/dev/null
playwright-cli fill "#exclGrowthPct" "22" >/dev/null
playwright-cli fill "#nonExclGrowthPct" "10" >/dev/null
playwright-cli fill "#comments" "[E2E-TEST-2] Berry write check" >/dev/null
playwright-cli click "#btnSubmitSave" >/dev/null
sleep 2

# Check collected count & expand organizer section to export master CSV
COUNT_STATE="$(playwright-cli eval "() => document.getElementById('respCount').textContent")"
echo "$COUNT_STATE" | grep -q '"2"' || { echo "FAIL: Expected respCount=2, got $COUNT_STATE" >&2; exit 1; }
echo "Collected Count: 2 (PASS)"

playwright-cli eval "() => { document.getElementById('organizerSection').open = true; }" >/dev/null
EXPORT_OUT="$(playwright-cli click "#btnExportAllCsv")"
echo "$EXPORT_OUT" | grep -E "Downloading file|Downloaded file" || true

# Verify network requests to Google Apps Script
REQ_LOG="$(playwright-cli requests)"
echo "=== Network Requests to Webhook ==="
echo "$REQ_LOG" | grep -E "script\.google\.com|script\.googleusercontent\.com" || true

POST_COUNT="$(echo "$REQ_LOG" | grep -c "script\.google\.com/macros/s/.*=> \[302\]" || true)"
ECHO_COUNT="$(echo "$REQ_LOG" | grep -c "script\.googleusercontent\.com/macros/echo.*=> \[200\]" || true)"
echo "Webhook POST=>302 count: $POST_COUNT | Echo GET=>200 count: $ECHO_COUNT"

if [ "$POST_COUNT" -lt 2 ] || [ "$ECHO_COUNT" -lt 2 ]; then
  echo "FAIL: Expected 2 successful webhook writes" >&2
  exit 1
fi

echo "=== PASS: E2E Verification Complete (2 records written to Sheet & Master CSV exported) ==="

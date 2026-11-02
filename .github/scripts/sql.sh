#!/usr/bin/env bash
# Runs SQL on the Supabase project through the Management API.
#   .github/scripts/sql.sh "select 1"      or      .github/scripts/sql.sh -f file.sql
# Prints the JSON result (or writes it to $OUTFILE; nothing if QUIET=1).
# On failure prints the real error as a red annotation on the run page
# (always on stdout, never into $OUTFILE), then exits 1.
# Needs PROJECT_REF and SUPABASE_ACCESS_TOKEN in the environment.
set -euo pipefail
if [ "${1:-}" = "-f" ]; then QUERY=$(cat "$2"); LABEL="$2"; else QUERY="$1"; LABEL="query"; fi
BODY=$(jq -n --arg q "$QUERY" '{query: $q}')
OUT=$(mktemp)
CODE=$(curl -sS -o "$OUT" -w '%{http_code}' -X POST \
  "https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" -H "Content-Type: application/json" \
  --data-binary "$BODY") || CODE=000
if [ "$CODE" -lt 200 ] || [ "$CODE" -ge 300 ]; then
  MSG=$(jq -r '.message // .error // .msg // empty' "$OUT" 2>/dev/null || true)
  [ -z "$MSG" ] && MSG=$(head -c 600 "$OUT")
  echo "::error title=SQL failed in ${LABEL} (HTTP ${CODE})::$(printf '%s' "$MSG" | tr '\n' ' ' | cut -c1-800)"
  case "$CODE" in
    401|403) echo "::error title=Token problem::SUPABASE_ACCESS_TOKEN is wrong, expired, or lacks Database read-write access to this project." ;;
    404) echo "::error title=Project not found::SUPABASE_URL does not match a project this token can see." ;;
    000) echo "::error title=Network::Could not reach api.supabase.com" ;;
  esac
  exit 1
fi
if [ -n "${OUTFILE:-}" ]; then cp "$OUT" "$OUTFILE"; elif [ "${QUIET:-0}" != "1" ]; then cat "$OUT"; fi

#!/usr/bin/env bash
# Runs SQL on the Supabase project through the Management API.
#   .github/scripts/sql.sh "select 1"      or      .github/scripts/sql.sh -f file.sql
# Needs PROJECT_REF and SUPABASE_ACCESS_TOKEN in the environment.
set -euo pipefail
if [ "${1:-}" = "-f" ]; then QUERY=$(cat "$2"); else QUERY="$1"; fi
BODY=$(jq -n --arg q "$QUERY" '{query: $q}')
CODE=$(curl -sS -o /tmp/sql_out.json -w '%{http_code}' -X POST \
  "https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query" \
  -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" -H "Content-Type: application/json" \
  --data-binary "$BODY")
if [ "$CODE" -lt 200 ] || [ "$CODE" -ge 300 ]; then
  echo "::error title=SQL failed (HTTP $CODE)::$(head -c 600 /tmp/sql_out.json)"
  [ "$CODE" = "401" ] || [ "$CODE" = "403" ] && echo "::error::SUPABASE_ACCESS_TOKEN is wrong or has no access to this project."
  exit 1
fi
cat /tmp/sql_out.json

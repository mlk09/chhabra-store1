#!/usr/bin/env bash
# Writes .env (public build settings) from GitHub Secrets. Missing Supabase
# details → a Demo-only build (the app still works, with the sample shop).
set -euo pipefail
URL=$(.github/scripts/normalize_supabase_url.sh "${RAW_URL:-}" 2>/dev/null || true)
KEY=$(printf '%s' "${RAW_KEY:-}" | tr -d '[:space:]"')
OWNER="${GITHUB_REPOSITORY%%/*}"
REPO="${GITHUB_REPOSITORY#*/}"
WEB="https://${OWNER,,}.github.io/${REPO}/app/"
if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "::warning title=Demo-only build::SUPABASE_URL / SUPABASE_ANON_KEY secrets are missing or invalid. The app will run in Demo mode."
  URL=""; KEY=""
fi
printf 'SUPABASE_URL=%s\nSUPABASE_ANON_KEY=%s\nSHOP_SLUG=chhabra-general-store\nWEB_APP_URL=%s\n' "$URL" "$KEY" "$WEB" > .env

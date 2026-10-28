#!/usr/bin/env bash
# Cleans a pasted Supabase URL: trims spaces/quotes, adds https://, drops any
# path (/rest/v1, /dashboard/...), accepts a bare project ref, and accepts a
# dashboard link (supabase.com/dashboard/project/<ref>). Prints the clean URL
# or exits 1 with a hint that never reveals the value.
raw="$1"
v=$(printf '%s' "$raw" | tr -d '[:space:]"'"'"'<>')
ref=""
if [[ "$v" =~ supabase\.com/dashboard/project/([a-z0-9]{15,30}) ]]; then
  ref="${BASH_REMATCH[1]}"
elif [[ "${v,,}" =~ ^(https?://)?([a-z0-9]{15,30})\.supabase\.(co|in)(/.*)?$ ]]; then
  ref="${BASH_REMATCH[2]}"
elif [[ "${v,,}" =~ ^[a-z0-9]{15,30}$ ]]; then
  ref="${v,,}"
fi
if [ -n "$ref" ]; then
  echo "https://${ref}.supabase.co"
  exit 0
fi
{
  echo "SUPABASE_URL could not be understood. Hints (value hidden):"
  echo "  length: ${#v}"
  [[ "$v" == http* ]] && echo "  starts with http: yes" || echo "  starts with http: NO"
  [[ "$v" == *supabase.co* ]] && echo "  contains supabase.co: yes" || echo "  contains supabase.co: NO"
  [[ "${v,,}" == *xxxx* ]] && echo "  ⚠ still contains the example 'xxxx' — paste YOUR Project URL"
  [[ "$v" == eyJ* || "$v" == sb_* ]] && echo "  ⚠ this looks like a KEY, not the URL — put the Project URL here"
} >&2
exit 1

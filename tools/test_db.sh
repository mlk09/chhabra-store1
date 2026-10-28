#!/usr/bin/env bash
# Runs every migration + the SQL tests on a throw-away Postgres database.
# Locally: PGHOST=/tmp PGPORT=5433 tools/test_db.sh     CI: uses the postgres service.
set -euo pipefail
cd "$(dirname "$0")/../supabase"
DB="${TEST_DB:-kirana_test}"
P=(psql -X -q -t -A -v ON_ERROR_STOP=1 -U "${PGUSER:-postgres}")
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
"${P[@]}" -d "$DB" -f tests/00_supabase_stubs.sql 2>&1 | grep -v -E 'wal_level|logical' || true
for f in migrations/*.sql; do echo "▶ $f"; "${P[@]}" -d "$DB" -f "$f"; done
"${P[@]}" -d "$DB" -f seed/seed.sql
"${P[@]}" -d "$DB" -f seed/seed.sql   # seed must be safe to re-run
"${P[@]}" -d "$DB" -f tests/01_test_helpers.sql
for f in tests/[1-9]*_test.sql; do
  echo "▶ $f"
  "${P[@]}" -d "$DB" -f "$f" 2>&1 | sed -E "s/^psql:[^ ]+ (NOTICE|INFO):  /  /" | grep -v "^$"
done
"${P[@]}" -d postgres -c "drop database $DB" >/dev/null
echo "✔ all database tests passed"

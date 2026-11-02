#!/usr/bin/env bash
# Load test on a THROW-AWAY Postgres database (never the real Supabase project):
#   3,000 products · 2,000 customers · CLIENTS people ordering at the same time,
#   the shop accepting/cancelling orders meanwhile, double taps, and shop browsing.
# Then checks every order, rupee and packet (supabase/load/90_verify.sql).
#   Locally: PGHOST=/var/run/postgresql PGUSER=postgres tools/load_test.sh
#   CI:      Actions → load-test
set -euo pipefail
cd "$(dirname "$0")/../supabase"
DB="${LOAD_DB:-kirana_load}"
CLIENTS="${CLIENTS:-50}"     # people ordering at the same moment
SECONDS_RUN="${SECONDS_RUN:-60}"
P=(psql -X -q -v ON_ERROR_STOP=1 -U "${PGUSER:-postgres}")

"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
"${P[@]}" -d "$DB" -f tests/00_supabase_stubs.sql 2>&1 | grep -v -E 'wal_level|logical' || true
for f in migrations/*.sql; do "${P[@]}" -d "$DB" -f "$f" >/dev/null; done
"${P[@]}" -d "$DB" -f seed/seed.sql >/dev/null
"${P[@]}" -d "$DB" -f load/00_setup.sql >/dev/null
"${P[@]}" -d "$DB" -c "vacuum analyze" >/dev/null
echo "✔ test shop ready: 3,000 products, 2,000 customers"

PB=(pgbench -n -U "${PGUSER:-postgres}" "$DB")
echo
echo "▶ 1. Opening the shop: $CLIENTS visitors loading the product list at once (15 s)"
"${PB[@]}" -c "$CLIENTS" -j 4 -T 15 -f load/catalog.pgbench 2>&1 | grep -E 'latency average|tps|failed'
"${P[@]}" -d "$DB" -t -A -c "select 'full product list size: ' || pg_size_pretty(sum(length(x::text))::bigint) || ' (before gzip)' from (
  select p.*, (select json_agg(v) from public.product_variants v where v.product_id = p.id) pv
  from public.products p where p.shop_id = 'e0000000-0000-0000-0000-000000000001') x"

echo
echo "▶ 2. Rush hour: $CLIENTS customers ordering at once + the shop working on orders + double taps (${SECONDS_RUN} s)"
"${PB[@]}" -c "$CLIENTS" -j 4 -T "$SECONDS_RUN" \
  -f load/order.pgbench@85 -f load/owner.pgbench@12 -f load/dup.pgbench@3 2>&1 | grep -E 'transactions|latency average|tps|failed'

echo
echo "▶ 3. Checks"
"${P[@]}" -d "$DB" -f load/90_verify.sql | tee /tmp/load_verify.txt
if grep -q 'FAIL' /tmp/load_verify.txt; then echo "✘ some checks failed"; exit 1; fi
echo "✔ all checks passed"

#!/bin/bash
# Runs Supabase's database advisors (splinter: the dashboard's Security and
# Performance Advisors) against the LOCAL database and fails on any WARN or
# ERROR finding that isn't accepted in supabase/advisors-accepted.txt.
# Read-only (one read-only transaction). Needs a running `supabase start`.
#
# Usage: supabase/scripts/advisors.sh            (from the repo root)
set -euo pipefail
cd "$(dirname "$0")/../.."

SPLINTER_SHA=cc529aa9d3eeffd2e64576c7591e60b22abd205c   # supabase/splinter, pinned
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -sSfL "https://raw.githubusercontent.com/supabase/splinter/$SPLINTER_SHA/splinter.sql" -o "$work/splinter.sql"

db=$(docker ps --format '{{.Names}}' | grep -m1 '^supabase_db_')
docker cp "$work/splinter.sql" "$db:/tmp/splinter.sql" >/dev/null
docker exec "$db" psql -U postgres -d postgres -At -F '|' -v ON_ERROR_STOP=1 \
  -c "begin read only;" -f /tmp/splinter.sql -c "rollback;" > "$work/findings.txt"

grep -v '^#' supabase/advisors-accepted.txt | sed '/^\s*$/d' | sort -u > "$work/accepted.txt"
awk -F'|' 'NF >= 10 && ($3 == "WARN" || $3 == "ERROR") { print $NF "\t" $3 "\t" $7 }' "$work/findings.txt" \
  | sort -u > "$work/warnings.tsv"
cut -f1 "$work/warnings.tsv" | sort -u > "$work/keys.txt"

new=$(comm -23 "$work/keys.txt" "$work/accepted.txt")
stale=$(comm -13 "$work/keys.txt" "$work/accepted.txt")
echo "advisors: $(wc -l < "$work/keys.txt" | tr -d ' ') WARN/ERROR findings, $(wc -l < "$work/accepted.txt" | tr -d ' ') accepted"
if [ -n "$stale" ]; then
  echo "accepted but no longer found (remove from supabase/advisors-accepted.txt):"
  echo "$stale" | sed 's/^/  /'
fi
if [ -n "$new" ]; then
  echo "NEW findings (fix them, or accept with a reason in supabase/advisors-accepted.txt):"
  while read -r key; do grep -F "$key"$'\t' "$work/warnings.tsv" | cut -f2,3 | sed "s/^/  $key: /"; done <<< "$new"
  exit 1
fi
echo "advisors: OK"

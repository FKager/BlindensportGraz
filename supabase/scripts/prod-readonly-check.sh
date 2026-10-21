#!/bin/zsh
# Read-only checks against a Supabase project (default: prod). Writes nothing.
#   1. budget_entries count (after the CloudKit cutover)
#   2. the same person on one team twice (member-backed + user-backed
#      team_memberships) — the duplicate names in the "Anwesenheit" list
#
# Usage: supabase/scripts/prod-readonly-check.sh [prod|staging]
# Runs `supabase login` first if the CLI token is invalid.
set -euo pipefail

case "${1:-prod}" in
  prod)    REF=dehtuoejbnunehevchtg ;;
  staging) REF=xlllxpmkxmcolukmcmoi ;;
  *) echo "usage: $0 [prod|staging]"; exit 2 ;;
esac
if ! supabase projects list >/dev/null 2>&1; then
  if [[ -t 0 ]]; then
    echo "Supabase CLI token invalid — logging in…" >&2
    supabase login
  else
    echo "Supabase CLI token invalid. Run 'supabase login' in a normal Terminal window" >&2
    echo "(it needs a TTY for the browser flow), then re-run this script." >&2
    exit 1
  fi
fi

# Management API token: env var, else the CLI's Keychain entry, else its file.
token() {
  if [[ -n ${SUPABASE_ACCESS_TOKEN:-} ]]; then print -r -- $SUPABASE_ACCESS_TOKEN; return; fi
  local t
  t=$(security find-generic-password -s "Supabase CLI" -w 2>/dev/null || true)
  [[ $t == go-keyring-base64:* ]] && t=$(print -r -- ${t#go-keyring-base64:} | base64 -D)
  if [[ -n $t ]]; then print -r -- $t; else cat $HOME/.supabase/access-token; fi
}

# SQL through the Management API (same as cutover.sh). Prints rows as lines.
sql() {
  local title=$1
  echo "== $title"
  python3 -c 'import json,sys; print(json.dumps({"query": sys.stdin.read()}))' \
    | curl -sS -f -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
        -H "Authorization: Bearer $(token)" -H "Content-Type: application/json" --data-binary @- \
    | python3 -c 'import json,sys
rows = json.load(sys.stdin)
print("  (no rows)") if not rows else [print(" ", r) for r in rows]'
}

sql "budget_entries" <<'SQL'
select count(*) as budget_entries, max(created_at) as newest from public.budget_entries
SQL

sql "Javornik: team memberships" <<'SQL'
select t.name as team, tm.id as membership, tm.member_id, tm.user_id, tm.role,
       coalesce(m.first_name || ' ' || m.last_name, p.first_name || ' ' || p.last_name) as name,
       (select count(*) from public.attendances a where a.membership_id = tm.id) as attendances
from public.team_memberships tm
join public.teams t on t.id = tm.team_id
left join public.members m on m.id = tm.member_id
left join public.profiles p on p.id = tm.user_id
where m.last_name ilike '%javornik%' or p.last_name ilike '%javornik%'
order by t.name
SQL

sql "Same person twice on a team (user-backed row + member-backed row)" <<'SQL'
select t.name as team,
       um.id as user_membership, mm.id as member_membership,
       p.first_name || ' ' || p.last_name as account_name,
       m.first_name || ' ' || m.last_name as roster_name,
       case when aa.member_id = m.id then 'approval link' else 'same name' end as matched_by
from public.team_memberships um
join public.profiles p on p.id = um.user_id
left join public.account_approvals aa on aa.user_id = um.user_id
join public.team_memberships mm on mm.team_id = um.team_id and mm.member_id is not null and mm.id <> um.id
join public.members m on m.id = mm.member_id
join public.teams t on t.id = um.team_id
where um.member_id is null
  and (aa.member_id = m.id
       or (lower(p.first_name) = lower(m.first_name) and lower(p.last_name) = lower(m.last_name)))
order by t.name, roster_name
SQL

#!/bin/zsh
# Club-data cutover (CloudKit -> Supabase) and push setup, for staging and prod.
# Plan: ~/.claude/plans/melodic-cuddling-magpie.md
#
# Usage: supabase/scripts/cutover.sh <staging|prod> <step> [args]
#   preflight          read-only: migrations, row counts, secret NAMES
#   push-secrets       APNs + notify-schedule function secrets and Vault entries
#   db-push            apply pending migrations
#   functions          deploy notify-schedule
#   templates          auth e-mail templates (token_hash links)
#   copy-dry|copy-apply [--since ISO]   CloudKit -> Supabase (staging: CloudKit Development,
#                                       prod: CloudKit Production)
#   webadmin           write nuc:~/blindensport-webadmin/.env for this project and restart
#
# Never prints keys or secrets: they go through temp files (mode 600, deleted)
# or straight into HTTPS requests. Needs: supabase CLI logged in
# (~/.supabase/access-token), ~/.config/apns/AuthKey_<id>.p8,
# ~/.config/rootcli/*.pem, built RootCLI (swift build -c release).
set -euo pipefail
cd "$(dirname "$0")/../.."

TARGET=${1:-}; STEP=${2:-}; shift 2 2>/dev/null || true
case "$TARGET" in
  staging) REF=xlllxpmkxmcolukmcmoi
           CK_ENV=development
           CK_KEY_ID=88f56683911217e01f148bc3162b8e986f88a77ef58cdf050191d113757af6ae
           CK_PEM=$HOME/.config/rootcli/dev_private_key_pkcs8.pem ;;
  prod)    REF=dehtuoejbnunehevchtg
           CK_ENV=production
           CK_KEY_ID=d8f546e972fedea430f039addde22a9b0a98cb8dbd722c3058d7b572314057a5
           CK_PEM=$HOME/.config/rootcli/rootcli_private_key_pkcs8.pem ;;
  *) echo "usage: $0 <staging|prod> <step>"; exit 2 ;;
esac
URL=https://$REF.supabase.co
APNS_KEY_ID=JD22K7SHQY
APNS_TEAM_ID=5Q57Y9YT8J
APNS_P8=$HOME/.config/apns/AuthKey_$APNS_KEY_ID.p8
ROOTCLI=RootCLI/.build/release/rootcli
MGMT_TOKEN_FILE=$HOME/.supabase/access-token
echo "== $TARGET ($REF): $STEP" >&2

# SQL through the Management API (no DB password needed). Prints the JSON result.
sql() {
  python3 -c 'import json,sys; print(json.dumps({"query": sys.stdin.read()}))' \
    | curl -sS -f -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
        -H "Authorization: Bearer $(cat $MGMT_TOKEN_FILE)" -H "Content-Type: application/json" --data-binary @-
}

api_key() {   # api_key <sb_prefix> <legacy name>
  supabase projects api-keys --project-ref $REF --reveal -o json 2>/dev/null | python3 -c '
import json, sys
prefix, name = sys.argv[1], sys.argv[2]
k = json.load(sys.stdin)
p = next((x for x in k if (x.get("api_key") or "").startswith(prefix)), None) or next(x for x in k if x.get("name") == name)
print(p["api_key"])' "$1" "$2"
}

copy_env() {
  export SUPABASE_URL=$URL
  export SUPABASE_SERVICE_KEY=$(api_key sb_secret_ service_role)
  export CLOUDKIT_ENVIRONMENT=$CK_ENV CLOUDKIT_KEY_ID=$CK_KEY_ID CLOUDKIT_PRIVATE_KEY_PATH=$CK_PEM
}

case "$STEP" in
  preflight)
    supabase migration list --project-ref $REF 2>/dev/null | python3 -c 'import json, sys
m = json.load(sys.stdin)["migrations"]
pending = [x["local"] for x in m if not x.get("remote")]
print("migrations:", len(m), "local,", len(m) - len(pending), "applied, pending:", pending or "none")'
    sql <<'SQL' | python3 -c 'import json,sys; [print(" ", r) for r in json.load(sys.stdin)]'
select 'auth.users' as t, count(*) from auth.users
union all select 'user_roles', count(*) from public.user_roles
union all select 'account_approvals', count(*) from public.account_approvals
union all select 'member_private', count(*) from public.member_private
union all select t, n from (
  select 'club tables present' as t, count(*) as n from information_schema.tables
  where table_schema = 'public' and table_name in ('members','teams','events','attendances','team_memberships')) x
SQL
    if sql <<<"select 1 from public.events limit 1" >/dev/null 2>&1; then
      sql <<'SQL' | python3 -c 'import json,sys; [print(" ", r) for r in json.load(sys.stdin)]'
select 'members' as t, count(*) from public.members
union all select 'teams', count(*) from public.teams
union all select 'team_memberships', count(*) from public.team_memberships
union all select 'events/training', count(*) from public.events where kind = 'training'
union all select 'events/tournament', count(*) from public.events where kind = 'tournament'
union all select 'events/event', count(*) from public.events where kind = 'event'
union all select 'attendances', count(*) from public.attendances
union all select 'training_favorites', count(*) from public.training_favorites
union all select 'budget_entries', count(*) from public.budget_entries
union all select 'device_tokens', count(*) from public.device_tokens
SQL
      sql <<<"select name from vault.secrets where name like 'notify_schedule_%' order by 1" \
        | python3 -c 'import json,sys; print("  vault:", [r["name"] for r in json.load(sys.stdin)])'
    fi
    supabase secrets list --project-ref $REF -o json 2>/dev/null \
      | python3 -c 'import json,sys; print("  function secrets:", sorted(s["name"] for s in json.load(sys.stdin) if not s["name"].startswith("SUPABASE_")))' || true
    ;;

  push-secrets)
    [ -r "$APNS_P8" ] || { echo "missing $APNS_P8"; exit 1; }
    secret=$(openssl rand -hex 32)
    tmp=$(mktemp); chmod 600 $tmp
    trap 'rm -f $tmp' EXIT
    python3 - "$APNS_P8" > $tmp <<PY
import sys
p8 = open(sys.argv[1]).read().strip().replace("\n", "\\\\n")
print("APNS_KEY_ID=$APNS_KEY_ID")
print("APNS_TEAM_ID=$APNS_TEAM_ID")
print("APNS_TOPIC=it.a11y.BlindensportGraz")
print('APNS_PRIVATE_KEY="' + p8 + '"')
print("NOTIFY_SCHEDULE_SECRET=$secret")
PY
    supabase secrets set --project-ref $REF --env-file $tmp >/dev/null && echo "function secrets set"
    sql >/dev/null <<SQL
do \$\$
declare v_id uuid;
begin
  select id into v_id from vault.secrets where name = 'notify_schedule_url';
  if v_id is null then perform vault.create_secret('$URL/functions/v1/notify-schedule', 'notify_schedule_url');
  else perform vault.update_secret(v_id, '$URL/functions/v1/notify-schedule'); end if;
  select id into v_id from vault.secrets where name = 'notify_schedule_secret';
  if v_id is null then perform vault.create_secret('$secret', 'notify_schedule_secret');
  else perform vault.update_secret(v_id, '$secret'); end if;
end
\$\$;
SQL
    echo "vault entries set (notify_schedule_url, notify_schedule_secret)"
    unset secret
    ;;

  db-push)
    supabase db push --project-ref $REF --yes
    ;;

  functions)
    supabase functions deploy notify-schedule --project-ref $REF --no-verify-jwt
    ;;

  templates)
    python3 - <<'PY' | curl -sS -f -X PATCH "https://api.supabase.com/v1/projects/$REF/config/auth" \
        -H "Authorization: Bearer $(cat $MGMT_TOKEN_FILE)" -H "Content-Type: application/json" \
        --data-binary @- -o /dev/null -w "templates: HTTP %{http_code}\n"
import json
t = "supabase/templates/"
print(json.dumps({
    "mailer_templates_recovery_content": open(t + "recovery.html").read(),
    "mailer_templates_confirmation_content": open(t + "confirmation.html").read(),
    "mailer_templates_email_change_content": open(t + "email_change.html").read(),
}))
PY
    ;;

  copy-dry)   copy_env; $ROOTCLI cloudkit-copy-to-supabase --dry-run "$@" ;;
  copy-apply) copy_env; $ROOTCLI cloudkit-copy-to-supabase --apply "$@" ;;

  webadmin)
    anon=$(api_key sb_publishable_ anon); secret=$(api_key sb_secret_ service_role)
    printf 'SUPABASE_URL=%s\nSUPABASE_ANON_KEY=%s\nSUPABASE_SERVICE_KEY=%s\n' "$URL" "$anon" "$secret" \
      | ssh franz@nuc "umask 077 && cat > ~/blindensport-webadmin/.env && cd ~/blindensport-webadmin && docker compose -f compose.traefik.yml up -d 2>&1 | tail -2"
    unset anon secret
    echo "webadmin on nuc now uses $TARGET ($REF)"
    ;;

  *) echo "unknown step '$STEP'"; exit 2 ;;
esac

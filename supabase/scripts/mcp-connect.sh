#!/bin/zsh
# Connects Claude Code on this Mac to the Blindensport Graz MCP server, in a
# terminal, with no browser: it signs in with your account, creates a personal
# token and registers it with Claude Code. Start Claude Code again afterwards.
#
# Usage: supabase/scripts/mcp-connect.sh <prod|staging>
#   prod     https://bs.a11y.it, registered as "blindensport"
#   staging  the local staging web UI on 127.0.0.1:8083, as "blindensport-staging"
#
# Needs a coach, admin or root account with a password. The password goes only
# to the web UI and is never shown or stored. The token ends up in Claude Code's
# settings file (~/.claude.json, for this project only); revoke it in the web
# UI under KI-Zugang. MCP_BASE overrides the address, for testing.
set -euo pipefail

case "${1:-}" in
  prod)    BASE=${MCP_BASE:-https://bs.a11y.it};    SERVER=blindensport ;;
  staging) BASE=${MCP_BASE:-http://127.0.0.1:8083}; SERVER=blindensport-staging ;;
  *) sed -n 2,13p "$0"; exit 2 ;;
esac

read "email?E-Mail ($1): "
read -s "password?Passwort: "; print
jar=$(mktemp); out=$(mktemp); trap 'rm -f $jar $out' EXIT
body() { KEY1=$1 VAL1=$2 KEY2=$3 VAL2=$4 python3 -c 'import json, os; print(json.dumps({os.environ["KEY1"]: os.environ["VAL1"], os.environ["KEY2"]: os.environ["VAL2"]}))'; }
post() { curl -sS -o $out -w '%{http_code}' -b $jar -c $jar -X POST "$BASE$1" -H 'Content-Type: application/json' -H 'X-Requested-With: blindensport-admin' --data-binary @-; }
fail() { print "$1: $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("reason","?"))' $out 2>/dev/null)"; exit 1; }

[ "$(body email "$email" password "$password" | post /api/session)" = 200 ] || fail "Anmeldung fehlgeschlagen"
[ "$(body password "$password" label "Claude Code $(hostname -s)" | post /api/mcp-tokens)" = 201 ] || fail "Kein Token erstellt"
unset password
token=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' $out)
claude mcp remove $SERVER -s local >/dev/null 2>&1 || true
claude mcp add --transport http --scope local $SERVER $BASE/mcp --header "Authorization: Bearer $token" >/dev/null
unset token
print "Verbunden als $SERVER ($BASE). Jetzt Claude Code neu starten: claude --continue"

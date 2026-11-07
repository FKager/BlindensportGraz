#!/bin/zsh
# Gives Claude Code on this Mac access to the MCP server against STAGING, in a
# terminal, with no browser. The web UI must be running on 127.0.0.1:8083.
#
# Usage: supabase/scripts/staging-mcp.sh connect
#
# Asks for your staging email and password, creates a personal token and
# registers it with Claude Code. Start Claude Code again afterwards. The token
# ends up in Claude Code's settings file, and the password goes only to the
# local web UI. Revoke the token in the web UI under KI-Zugang.
set -euo pipefail

BASE=http://127.0.0.1:8083
SERVER=blindensport-staging
[ "${1:-}" = connect ] || { sed -n 2,10p "$0"; exit 2; }

read "email?Staging email: "
read -s "password?Password: "; print
jar=$(mktemp); out=$(mktemp); trap 'rm -f $jar $out' EXIT
body() { KEY1=$1 VAL1=$2 KEY2=$3 VAL2=$4 python3 -c 'import json, os; print(json.dumps({os.environ["KEY1"]: os.environ["VAL1"], os.environ["KEY2"]: os.environ["VAL2"]}))'; }
post() { curl -sS -o $out -w '%{http_code}' -b $jar -c $jar -X POST "$BASE$1" -H 'Content-Type: application/json' -H 'X-Requested-With: blindensport-admin' --data-binary @-; }
fail() { print "$1: $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("reason","?"))' $out 2>/dev/null)"; exit 1; }

[ "$(body email "$email" password "$password" | post /api/session)" = 200 ] || fail "Sign-in failed"
[ "$(body password "$password" label "Claude Code $(hostname -s)" | post /api/mcp-tokens)" = 201 ] || fail "No token created"
unset password
token=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' $out)
claude mcp remove $SERVER -s local >/dev/null 2>&1 || true
claude mcp add --transport http --scope local $SERVER $BASE/mcp --header "Authorization: Bearer $token" >/dev/null
print "Connected. Now run: claude --continue"

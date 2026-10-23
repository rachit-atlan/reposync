#!/usr/bin/env bash
# Probes repository registration for agent-registry-action#44 / registry-cli#218 review.
# Prints statuses, ids and version fields only; the key reaches curl on stdin, never argv.
set -euo pipefail
API=https://api.atlan.com
REMOTE=https://github.com/rachit-atlan/reposync
out=$(mktemp); trap 'rm -f "$out"' EXIT
call() { # method path [json-body] -> sets $code, body in $out
  local method=$1 path=$2 body=${3:-}
  local args=(-sS -o "$out" -w '%{http_code}' -X "$method" "$API$path" -K -)
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' --data "$body")
  code=$(printf 'header = "Authorization: Bearer %s"\n' "$AIREG_TOKEN_ATLAN" | curl "${args[@]}")
}
show() { echo "$1 -> $code $(jq -c "$2" "$out" 2>/dev/null || echo '(no json)')"; }

call GET "/registry/v1/workspaces?limit=200"
W=$(jq -r '.items[] | select(.name=="registry-cli-test") | .id' "$out"); echo "workspace registry-cli-test: $W"
call GET "/registry/v1/artifacts/skill?filter%5Bworkspace_id%5D%5Beq%5D=$W&filter%5Bname%5D%5Beq%5D=e2e1023-fresh2&limit=5"
S=$(jq -r '.items[0].id // empty' "$out"); echo "skill e2e1023-fresh2: $S"

echo "== legacy registration (what the adapter uses today)"
call POST /registry/v1/repos "$(jq -nc --arg w "$W" --arg u "$REMOTE" '{workspace_id:$w, source_type:"git", source_uri:$u}')"
show "POST /registry/v1/repos" '{id, workspace_id, source_uri}'
LEGACY=$(jq -r '.id // empty' "$out")
call GET "/registry/v1/artifacts/repo/$LEGACY"
show "GET repo artifact at the legacy id" '{id, name, workspace_id}'

echo "== canonical registration, twice"
for n in 1 2; do
  call POST /repo/v1/repos "$(jq -nc --arg w "$W" --arg u "$REMOTE" '{workspace_id:$w, remote_url:$u}')"
  show "POST /repo/v1/repos #$n" '{id, name, workspace_id, write_index, version_ordinal, is_latest, title, detail}'
done
REPO=$(jq -r '.id // empty' "$out")
call GET "/registry/v1/artifacts/repo/$REPO"
show "GET repo artifact at the canonical id" '{id, name, workspace_id, write_index}'

echo "== link the skill to the canonical repo artifact"
call POST "/registry/v1/artifacts/skill/$S/relationships" "$(jq -nc --arg r "$REPO" '{rel_type:"sourced_from", to_id:$r, attributes:{path:"e2e1023/debug/fresh/skills/e2e1023-fresh2"}}')"
show "POST skill relationships -> canonical repo" '{rel_type, to_id, title, detail}'
call GET "/registry/v1/artifacts/skill/$S/relationships?filter%5Brel_type%5D%5Beq%5D=sourced_from&limit=5"
show "GET skill sourced_from" '[.items[]? | {to_id, attributes}]'

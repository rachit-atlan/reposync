#!/usr/bin/env bash
# Second probe: how a repo artifact reads back, and whether a name lookup finds it.
# Prints statuses, field names and URI fields only; the key reaches curl on stdin.
set -euo pipefail
API=https://api.atlan.com
W=workspace_01m36rz0zdfc1ttjvtj0h9b87j
REPO=repo_01m51yr5wxe7088jrz54tc6000
S=skill_01m5ky9e2me14b7zdc32grfty1
out=$(mktemp); trap 'rm -f "$out"' EXIT
get() { code=$(printf 'header = "Authorization: Bearer %s"\n' "$AIREG_TOKEN_ATLAN" | curl -sS -o "$out" -w '%{http_code}' "$API$1" -K -); }
uris='[paths(type == "string") as $p | select(($p | map(tostring) | join(".")) | test("uri|url|remote|name")) | {key: ($p | map(tostring) | join(".")), value: getpath($p)}] | from_entries'
for path in "/repo/v1/repos/$REPO" "/registry/v1/artifacts/repo/$REPO" "/registry/v1/repos/$REPO"; do
  get "$path"; echo "GET $path -> $code"; echo "  keys: $(jq -c 'keys' "$out" 2>/dev/null)"; echo "  uri fields: $(jq -c "$uris" "$out" 2>/dev/null)"
done
for name in "github.com/rachit-atlan/reposync" "https://github.com/rachit-atlan/reposync"; do
  q=$(jq -rn --arg w "$W" --arg n "$name" '"filter[workspace_id][eq]=\($w|@uri)&filter[name][eq]=\($n|@uri)&limit=5"')
  get "/registry/v1/artifacts/repo?$q"; echo "LIST repo by name '$name' -> $code ids=$(jq -c '[.items[]?.id]' "$out")"
done
q=$(jq -rn --arg w "$W" '"filter[workspace_id][eq]=\($w|@uri)&limit=50"')
get "/registry/v1/artifacts/repo?$q"; echo "LIST repos in workspace -> $code $(jq -c '[.items[]? | {id, name}]' "$out")"
get "/registry/v1/artifacts/skill/$S/relationships?filter%5Brel_type%5D%5Beq%5D=sourced_from&limit=5"
echo "GET skill sourced_from -> $code first item: $(jq -c '.items[0] | {rel_type, relationship_status, to, attributes}' "$out")"

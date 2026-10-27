#!/usr/bin/env bash
# Creates an agent through the API as atlan-link-agent does (create), or lists agents by that name
# (verify). Installs aireg and the signed adapter as the Action does. Prints IDs, never the key.
set -euo pipefail
mode=$1; name=v1-1027-legacy; ws_name=registry-cli-test
home=$(mktemp -d); trap 'rm -rf "$home"' EXIT
export HOME="$home" AIREG_HOME="$home/.aireg" AIREG_USER_SCOPE="$home/registry" AIREG_DISABLE_UPDATE_CHECK=1 NO_COLOR=1 DO_NOT_TRACK=1
curl -fsSL --proto '=https' https://aireg.sh/artifacts/v0.1.2/aireg-linux-amd64 -o "$home/aireg"
echo "353c7ad92efea87d12e22bfdaba00f545317ea926791bd859eb8fe6407269785  $home/aireg" | sha256sum -c -
chmod +x "$home/aireg"
bin=$("$home/aireg" self update --json | jq -r 'if .data.action == "updated" then .data.bin else empty end')
bin=${bin:-$home/aireg}
"$bin" adapter install atlan --yes >/dev/null
api() { "$bin" atlan api "$@" --registry atlan --json | jq '.data.body'; }

ws=$(api get /registry/v1/workspaces | jq -r --arg n "$ws_name" '[.items[] | select(.name == $n or .slug == $n or .handle == $n)] | if length == 1 then .[0].id else error("workspace \($n): \(length) matches") end')
echo "workspace $ws_name = $ws"

if [ "$mode" = create ]; then
  jq -n --arg ws "$ws" --arg n "$name" '{workspace_id: $ws, name: $n,
    description: "Throwaway agent created through the API as atlan-link-agent does, then exported by the manifest, for the v1 test on reposync, 2026-10-27. Safe to delete.",
    instructions: "You review pull requests.", source_type: "git", source_id: ".atlan/agents/\($n).yaml"}' > "$home/agent.json"
  mkdir -m 700 "$home/cred"
  created=$("$bin" atlan api post /agent/v1/agents --registry atlan --input "$home/agent.json" \
    --output-file "$home/cred/agent.json" --output-field identity --json | jq '.data.body')
  agent=$(jq -r '.id // .agent.id // empty' <<<"$created")
  echo "created agent $name = $agent (key written to a private temp file, then deleted)"
  repo=$(api get "/registry/v1/artifacts/repo?filter%5Bworkspace_id%5D%5Beq%5D=$ws&filter%5Bname%5D%5Beq%5D=github.com%2Frachit-atlan%2Freposync&limit=1" | jq -r '.items[0].id')
  echo "repository artifact = $repo"
  jq -n --arg r "$repo" --arg n "$name" '{rel_type: "sourced_from", to_id: $r, attributes: {path: ".atlan/agents/\($n).yaml"}}' > "$home/edge.json"
  api post "/registry/v1/artifacts/agent/$agent/relationships" --input "$home/edge.json" | jq -c '{id, rel_type, to_id}'
fi

echo "agents named $name in $ws_name:"
api get "/registry/v1/artifacts/agent?filter%5Bworkspace_id%5D%5Beq%5D=$ws&filter%5Bname%5D%5Beq%5D=$name&limit=10" \
  | jq -c '.items[] | {id, name, source_type, source_id, version_label, is_latest}'
if [ "$mode" = verify ]; then
  agent=$(api get "/registry/v1/artifacts/agent?filter%5Bworkspace_id%5D%5Beq%5D=$ws&filter%5Bname%5D%5Beq%5D=$name&limit=1" | jq -r '.items[0].id')
  echo "relationships of $agent:"
  api get "/registry/v1/artifacts/agent/$agent/relationships" | jq -c '(.items // .)[] | {rel_type, to_id, to_kind, attributes, status: (.status // .relationship_status)}'
fi
if [ "$mode" = skills ]; then
  echo "skills in $ws_name whose version is not SemVer:"
  api get "/registry/v1/artifacts/skill?filter%5Bworkspace_id%5D%5Beq%5D=$ws&limit=200" \
    | jq -c '.items[] | select((.version_label // "") | test("^[0-9]+\\.[0-9]+\\.[0-9]+$") | not) | {id, name, version_label, source_type, source_id, artifact_status}'
fi

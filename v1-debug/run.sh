#!/usr/bin/env bash
# Installs aireg and the signed atlan adapter as Registry Sync v1.0.0 does, then publishes with the
# source build of the same aireg so the request log can load. $1 names the run.
set -euo pipefail
name=$1
home=$(mktemp -d); trap 'rm -rf "$home"' EXIT
export HOME="$home" AIREG_HOME="$home/.aireg" AIREG_USER_SCOPE="$home/registry" AIREG_DISABLE_UPDATE_CHECK=1 NO_COLOR=1 DO_NOT_TRACK=1
echo "::group::install ($name)"
curl -fsSL --proto '=https' https://aireg.sh/artifacts/v0.1.2/aireg-linux-amd64 -o "$home/aireg"
echo "353c7ad92efea87d12e22bfdaba00f545317ea926791bd859eb8fe6407269785  $home/aireg" | sha256sum -c -
chmod +x "$home/aireg"
bin=$("$home/aireg" self update --json | jq -r 'if .data.action == "updated" then .data.bin else empty end')
bin=${bin:-$home/aireg}
"$bin" --version
"$bin" adapter install atlan --yes
echo "::endgroup::"
log="$RUNNER_TEMP/$name.log"; : > "$log"
echo "::group::publish ($name)"
E2E_FETCH_LOG="$log" NODE_OPTIONS="--import=$LOGGER" node "$AIREG_MAIN" publish --yes 2>&1 || echo "exit $?"
echo "--- requests"
cat "$log"
echo "::endgroup::"

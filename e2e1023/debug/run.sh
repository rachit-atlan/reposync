#!/usr/bin/env bash
# Runs aireg in an isolated home with the request log; $1 names the scenario, $2 the project folder.
set -euo pipefail
name=$1; project=$2
home=$(mktemp -d); trap 'rm -rf "$home"' EXIT
export HOME="$home" AIREG_HOME="$home/.aireg" AIREG_USER_SCOPE="$home/.registry" AIREG_DISABLE_UPDATE_CHECK=1 NO_COLOR=1 DO_NOT_TRACK=1
aireg() { node "$AIREG_MAIN" "$@"; }
log="$RUNNER_TEMP/$name.log"; : > "$log"
echo "::group::$name"
# The released aireg installs and verifies the adapter, as the Action does; the source build then runs it.
released="$home/aireg-released"
curl -fsSL --proto '=https' -o "$released" "https://aireg.sh/artifacts/v0.1.2/aireg-linux-amd64"
echo "353c7ad92efea87d12e22bfdaba00f545317ea926791bd859eb8fe6407269785  $released" | sha256sum -c --quiet
chmod 700 "$released"
updated=$("$released" self update --json | jq -r '.data.bin // empty')
[ -n "$updated" ] && released=$updated
"$released" --version
(cd "$project" && "$released" adapter install atlan --yes && aireg --version && \
  E2E_FETCH_LOG="$log" NODE_OPTIONS="--import=$LOGGER" aireg publish --yes 2>&1) || echo "exit $?"
echo "--- requests"
cat "$log"
echo "::endgroup::"

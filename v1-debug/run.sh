#!/usr/bin/env bash
# Runs aireg with the released atlan adapter, in an isolated home, with the request log.
# $1 names the run; the project is the repository root.
set -euo pipefail
name=$1
home=$(mktemp -d); trap 'rm -rf "$home"' EXIT
export HOME="$home" AIREG_HOME="$home/.aireg" AIREG_USER_SCOPE="$home/.registry" AIREG_DISABLE_UPDATE_CHECK=1 NO_COLOR=1 DO_NOT_TRACK=1
log="$RUNNER_TEMP/$name.log"; : > "$log"
echo "::group::$name"
node "$AIREG_MAIN" adapter install atlan --yes
E2E_FETCH_LOG="$log" NODE_OPTIONS="--import=$LOGGER" node "$AIREG_MAIN" publish --yes 2>&1 || echo "exit $?"
echo "--- requests"
cat "$log"
echo "::endgroup::"

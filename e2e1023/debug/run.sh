#!/usr/bin/env bash
# Runs aireg with the adapter build under test, in an isolated home, with the request log.
# $1 names the scenario, $2 the project folder.
set -euo pipefail
name=$1; project=$2
home=$(mktemp -d); trap 'rm -rf "$home"' EXIT
export HOME="$home" AIREG_HOME="$home/.aireg" AIREG_USER_SCOPE="$home/.registry" AIREG_DISABLE_UPDATE_CHECK=1 NO_COLOR=1 DO_NOT_TRACK=1
mkdir -p "$AIREG_HOME"
printf 'schemaVersion: 1\nrevision: 1\nadapters:\n  atlan: %s\naccounts: []\njobs: []\n' "$ADAPTER" > "$AIREG_HOME/config.yml"
log="$RUNNER_TEMP/$name.log"; : > "$log"
echo "::group::$name"
(cd "$project" && E2E_FETCH_LOG="$log" NODE_OPTIONS="--import=$LOGGER" node "$AIREG_MAIN" publish --yes 2>&1) || echo "exit $?"
echo "--- requests"
cat "$log"
echo "::endgroup::"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT=/data/sonic/时间统计/measure_sonic_vs.sh
EXPECTED=$'01-bazel-fully-cold\n02-make-fully-cold\n03-bazel-deps-retained\n04-make-deps-retained'
ACTUAL=$(RUN_DIR=/data/sonic/时间统计/logs/test CACHE_ROOT=/data/sonic/时间统计/cache/test "$SCRIPT" dry-run)
[[ "$ACTUAL" == "$EXPECTED" ]]

ERROR_FILE=$(mktemp)
TMP_RUN=$(mktemp -d /data/sonic/时间统计/logs/test.XXXXXX)
trap 'rm -f "$ERROR_FILE"; rm -rf "$TMP_RUN"' EXIT
if RUN_DIR=/data/sonic/时间统计/logs/test CACHE_ROOT=/data "$SCRIPT" validate >"$ERROR_FILE" 2>&1; then
    printf 'unsafe cache root was accepted\n' >&2
    exit 1
fi
[[ "$(<"$ERROR_FILE")" == *"unsafe CACHE_ROOT"* ]]

set +e
RUN_DIR="$TMP_RUN" CACHE_ROOT=/data/sonic/时间统计/cache/test "$SCRIPT" run-timed expected-failure bash -c 'printf "captured-output\\n"; exit 7'
STATUS=$?
set -e
[[ "$STATUS" -eq 7 ]]
[[ "$(<"$TMP_RUN/expected-failure/exit-code.txt")" == 7 ]]
[[ -s "$TMP_RUN/expected-failure/time.txt" ]]
[[ "$(<"$TMP_RUN/expected-failure/build.log")" == "captured-output" ]]
[[ -s "$TMP_RUN/expected-failure/command.txt" ]]

printf 'artifact-data\n' > "$TMP_RUN/artifact.bin"
RUN_DIR="$TMP_RUN" CACHE_ROOT=/data/sonic/时间统计/cache/test "$SCRIPT" verify-artifact artifact-check "$TMP_RUN/artifact.bin"
[[ -s "$TMP_RUN/artifact-check/artifact.txt" ]]
[[ "$(<"$TMP_RUN/artifact-check/artifact.txt")" == *"$(sha256sum "$TMP_RUN/artifact.bin" | cut -d' ' -f1)"* ]]

BLOCKER_LOG="$TMP_RUN/blockers.md" RUN_DIR="$TMP_RUN" CACHE_ROOT=/data/sonic/时间统计/cache/test "$SCRIPT" record-blocker expected-failure 'simulated blocker'
[[ "$(<"$TMP_RUN/blockers.md")" == *"expected-failure"* ]]
[[ "$(<"$TMP_RUN/blockers.md")" == *"simulated blocker"* ]]

RUN_DIR="$TMP_RUN" CACHE_ROOT=/data/sonic/时间统计/cache/test "$SCRIPT" record-environment test-env
[[ -s "$TMP_RUN/test-env/environment.txt" ]]
[[ "$(<"$TMP_RUN/test-env/environment.txt")" == *"git_head="* ]]

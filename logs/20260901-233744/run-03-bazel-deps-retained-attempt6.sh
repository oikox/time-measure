#!/usr/bin/env bash
set -u

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE=03-bazel-deps-retained-attempt6
STAGE_DIR="$RUN_DIR/$STAGE"
MEASURE=/data/sonic/时间统计/measure_sonic_vs.sh
ASCII_ROOT="$REPO/.measure/20260901-233744/bazel-fully-cold-attempt3"
OUTPUT_BASE="$ASCII_ROOT/output-base"
REPOSITORY_CACHE="$ASCII_ROOT/repository-cache"
EVIDENCE="$ASCII_ROOT/evidence-retained-attempt6"
ARTIFACT="$OUTPUT_BASE/execroot/_main/bazel-out/k8-opt/bin/platform/vs/sonic-vs.bin"

mkdir -p "$STAGE_DIR" "$EVIDENCE"
cd "$REPO" || exit 125
[[ ! -e "$ARTIFACT" ]] || exit 125
{
    du -sh "$OUTPUT_BASE" "$REPOSITORY_CACHE"
    if [[ -e "$OUTPUT_BASE/external" ]]; then du -sh "$OUTPUT_BASE/external"; fi
} > "$STAGE_DIR/cache-before-build.txt"

bazel --output_base="$OUTPUT_BASE" shutdown > "$STAGE_DIR/bazel-shutdown.log" 2>&1
status=$?
if (( status != 0 )); then exit "$status"; fi

RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE" \
    bazel --output_base="$OUTPUT_BASE" build \
    --repository_cache="$REPOSITORY_CACHE" \
    --repository_disable_download \
    --remote_cache= \
    --experimental_remote_downloader= \
    --profile="$EVIDENCE/profile.gz" \
    --build_event_json_file="$EVIDENCE/bep.json" \
    --show_progress_rate_limit=30 \
    platform/vs:sonic-vs-bin
status=$?
if [[ -f "$EVIDENCE/profile.gz" ]]; then cp "$EVIDENCE/profile.gz" "$STAGE_DIR/profile.gz"; fi
if [[ -f "$EVIDENCE/bep.json" ]]; then cp "$EVIDENCE/bep.json" "$STAGE_DIR/bep.json"; fi
if (( status == 0 )); then
    RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" verify-artifact "$STAGE" "$ARTIFACT"
    status=$?
fi
printf '%s\n' "$status" > "$STAGE_DIR/runner-status.tmp"
mv "$STAGE_DIR/runner-status.tmp" "$STAGE_DIR/runner-status.txt"
exit "$status"

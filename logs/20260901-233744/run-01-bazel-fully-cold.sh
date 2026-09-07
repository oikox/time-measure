#!/usr/bin/env bash
set -u

RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE_DIR="$RUN_DIR/01-bazel-fully-cold"
OUTPUT_BASE="$CACHE_ROOT/bazel-fully-cold/output-base"
REPOSITORY_CACHE="$CACHE_ROOT/bazel-fully-cold/repository-cache"

cd /data/sonic/sonic-dzf-time-measure || exit 125
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" /data/sonic/时间统计/measure_sonic_vs.sh run-timed 01-bazel-fully-cold \
    bazel --output_base="$OUTPUT_BASE" build \
    --repository_cache="$REPOSITORY_CACHE" \
    --remote_cache= \
    --experimental_remote_downloader= \
    --profile="$STAGE_DIR/profile.gz" \
    --build_event_json_file="$STAGE_DIR/bep.json" \
    --show_progress_rate_limit=30 \
    //platform/vs:sonic-vs-bin
status=$?
printf '%s\n' "$status" > "$STAGE_DIR/runner-status.tmp"
mv "$STAGE_DIR/runner-status.tmp" "$STAGE_DIR/runner-status.txt"
exit "$status"

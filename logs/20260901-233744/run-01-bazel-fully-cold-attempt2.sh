#!/usr/bin/env bash
set -u

RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE=01-bazel-fully-cold-attempt2
STAGE_DIR="$RUN_DIR/$STAGE"
ASCII_ROOT=/data/sonic/sonic-dzf-time-measure/.measure/20260901-233744/bazel-fully-cold-attempt2
OUTPUT_BASE="$ASCII_ROOT/output-base"
REPOSITORY_CACHE="$ASCII_ROOT/repository-cache"
EVIDENCE="$ASCII_ROOT/evidence"

cd /data/sonic/sonic-dzf-time-measure || exit 125
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" /data/sonic/时间统计/measure_sonic_vs.sh run-timed "$STAGE" \
    bazel --output_base="$OUTPUT_BASE" build \
    --repository_cache="$REPOSITORY_CACHE" \
    --remote_cache= \
    --experimental_remote_downloader= \
    --profile="$EVIDENCE/profile.gz" \
    --build_event_json_file="$EVIDENCE/bep.json" \
    --show_progress_rate_limit=30 \
    //platform/vs:sonic-vs-bin
status=$?
if [[ -f "$EVIDENCE/profile.gz" ]]; then cp "$EVIDENCE/profile.gz" "$STAGE_DIR/profile.gz"; fi
if [[ -f "$EVIDENCE/bep.json" ]]; then cp "$EVIDENCE/bep.json" "$STAGE_DIR/bep.json"; fi
printf '%s\n' "$status" > "$STAGE_DIR/runner-status.tmp"
mv "$STAGE_DIR/runner-status.tmp" "$STAGE_DIR/runner-status.txt"
exit "$status"

#!/usr/bin/env bash
set -u

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
SELECTIVE_CACHE="$CACHE_ROOT/bazel-kernel-p4lang"
STAGE=06-bazel-kernel-p4lang-cached
STAGE_DIR="$RUN_DIR/$STAGE"
PREP_DIR="$RUN_DIR/$STAGE-prep"
MEASURE=/data/sonic/时间统计/measure_sonic_vs.sh
ASCII_ROOT="$REPO/.measure/20260901-233744/bazel-fully-cold-attempt3"
OUTPUT_BASE="$ASCII_ROOT/output-base"
REPOSITORY_CACHE="$ASCII_ROOT/repository-cache"
EVIDENCE="$ASCII_ROOT/evidence-kernel-p4lang-cached"
ARTIFACT="$OUTPUT_BASE/execroot/_main/bazel-out/k8-opt/bin/platform/vs/sonic-vs.bin"
KERNEL_TARGET='@sonic_linux_kernel//:kernel_amd64'
PI_TARGET='@p4lang//:p4lang-pi_0.1.1-1.deb'
BMV2_TARGET='@p4lang//:p4lang-bmv2_1.15.0-9.deb'
P4C_TARGET='@p4lang//:p4lang-p4c_1.2.4.2-2.deb'
PI_LAYER_TARGET='@p4lang//:pi_runtime_layer'

clean_p4lang_outputs() {
    rm -f "$REPO"/target/debs/trixie/p4lang-*
    rm -rf \
        "$REPO/src/p4lang/p4lang-pi-0.1.1" \
        "$REPO/src/p4lang/p4lang-bmv2-1.15.0" \
        "$REPO/src/p4lang/p4lang-p4c-1.2.4.2"
    find "$REPO/src/p4lang" -maxdepth 1 -type f \
        \( -name 'p4lang-*.deb' -o -name 'p4lang-*.ddeb' -o -name 'p4lang-*.changes' -o -name 'p4lang-*.buildinfo' \) -delete
}

bazel_common=(
    --repository_cache="$REPOSITORY_CACHE"
    --repository_disable_download
    --remote_cache=
    --experimental_remote_downloader=
    --disk_cache=/data/sonic/时间统计/cache/20260901-233744/bazel-kernel-p4lang
    --action_env=BUILD_SKIP_TEST=y
    --action_env=HTTP_PROXY=http://127.0.0.1:9
    --action_env=HTTPS_PROXY=http://127.0.0.1:9
    --action_env=http_proxy=http://127.0.0.1:9
    --action_env=https_proxy=http://127.0.0.1:9
)

mkdir -p "$STAGE_DIR" "$PREP_DIR" "$EVIDENCE"
cd "$REPO" || exit 125
[[ "$REPO" == /data/sonic/sonic-dzf-time-measure ]] || exit 125
[[ "$SELECTIVE_CACHE" == /data/sonic/时间统计/cache/20260901-233744/bazel-kernel-p4lang ]] || exit 125

rm -rf "$SELECTIVE_CACHE"
mkdir -p "$SELECTIVE_CACHE"
bazel --output_base="$OUTPUT_BASE" clean > "$PREP_DIR/seed-clean.log" 2>&1 || exit $?
/usr/bin/time -v -o "$PREP_DIR/seed-time.txt" \
    bazel --output_base="$OUTPUT_BASE" build "${bazel_common[@]}" \
    "$KERNEL_TARGET" "$PI_TARGET" "$BMV2_TARGET" "$P4C_TARGET" "$PI_LAYER_TARGET" \
    > "$PREP_DIR/seed.log" 2>&1 || exit $?
du -sh "$SELECTIVE_CACHE" > "$PREP_DIR/disk-cache-size.txt"
find "$SELECTIVE_CACHE" -type f | wc -l > "$PREP_DIR/disk-cache-file-count.txt"

bazel --output_base="$OUTPUT_BASE" clean > "$PREP_DIR/probe-clean.log" 2>&1 || exit $?
clean_p4lang_outputs
/usr/bin/time -v -o "$PREP_DIR/probe-time.txt" \
    bazel --output_base="$OUTPUT_BASE" build "${bazel_common[@]}" \
    "$KERNEL_TARGET" "$PI_TARGET" "$BMV2_TARGET" "$P4C_TARGET" "$PI_LAYER_TARGET" \
    > "$PREP_DIR/probe.log" 2>&1 || exit $?
if grep -F 'Building Linux kernel' "$PREP_DIR/probe.log" >/dev/null; then exit 124; fi
if grep -F 'SONiC make (local)' "$PREP_DIR/probe.log" >/dev/null; then exit 125; fi
grep -F 'disk cache hit' "$PREP_DIR/probe.log" >/dev/null || exit 126

bazel --output_base="$OUTPUT_BASE" clean > "$PREP_DIR/formal-clean.log" 2>&1 || exit $?
clean_p4lang_outputs
[[ ! -e "$ARTIFACT" ]] || exit 125
bazel --output_base="$OUTPUT_BASE" shutdown > "$PREP_DIR/bazel-shutdown.log" 2>&1 || exit $?

RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE" \
    bazel --output_base="$OUTPUT_BASE" build "${bazel_common[@]}" \
    --profile="$EVIDENCE/profile.gz" \
    --build_event_json_file="$EVIDENCE/bep.json" \
    --show_progress_rate_limit=30 \
    platform/vs:sonic-vs-bin
status=$?
if [[ -f "$EVIDENCE/profile.gz" ]]; then cp "$EVIDENCE/profile.gz" "$STAGE_DIR/profile.gz"; fi
if [[ -f "$EVIDENCE/bep.json" ]]; then cp "$EVIDENCE/bep.json" "$STAGE_DIR/bep.json"; fi
if (( status == 0 )); then
    RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" verify-artifact "$STAGE" "$ARTIFACT" || status=$?
fi
if (( status == 0 )); then
    if grep -F 'Building Linux kernel' "$STAGE_DIR/build.log" >/dev/null; then status=120; fi
    if grep -F 'SONiC make (local)' "$STAGE_DIR/build.log" >/dev/null; then status=121; fi
    grep -F 'disk cache hit' "$STAGE_DIR/build.log" >/dev/null || status=122
fi
printf '%s\n' "$status" > "$STAGE_DIR/runner-status.tmp"
mv "$STAGE_DIR/runner-status.tmp" "$STAGE_DIR/runner-status.txt"
exit "$status"

#!/usr/bin/env bash
set -u

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE=06-bazel-kernel-p4lang-cached-attempt2
STAGE_DIR="$RUN_DIR/$STAGE"
PREP_DIR="$RUN_DIR/$STAGE-prep"
MEASURE=/data/sonic/时间统计/measure_sonic_vs.sh
ASCII_ROOT="$REPO/.measure/20260901-233744/bazel-fully-cold-attempt3"
OUTPUT_BASE="$ASCII_ROOT/output-base"
REPOSITORY_CACHE="$ASCII_ROOT/repository-cache"
EVIDENCE="$ASCII_ROOT/evidence-kernel-p4lang-cached-attempt2"
ARTIFACT="$OUTPUT_BASE/execroot/_main/bazel-out/k8-opt/bin/platform/vs/sonic-vs.bin"
KERNEL_TARGET='@sonic_linux_kernel//:kernel_amd64'
PI_TARGET='@p4lang//:p4lang-pi_0.1.1-1.deb'
BMV2_TARGET='@p4lang//:p4lang-bmv2_1.15.0-9.deb'
P4C_TARGET='@p4lang//:p4lang-p4c_1.2.4.2-2.deb'
PI_LAYER_TARGET='@p4lang//:pi_runtime_layer'

bazel_common=(
    --repository_cache="$REPOSITORY_CACHE"
    --repository_disable_download
    --remote_cache=
    --experimental_remote_downloader=
    --disk_cache=
    --action_env=BUILD_SKIP_TEST=y
    --action_env=HTTP_PROXY=http://127.0.0.1:9
    --action_env=HTTPS_PROXY=http://127.0.0.1:9
    --action_env=http_proxy=http://127.0.0.1:9
    --action_env=https_proxy=http://127.0.0.1:9
)

mkdir -p "$STAGE_DIR" "$PREP_DIR" "$EVIDENCE"
cd "$REPO" || exit 125
[[ "$REPO" == /data/sonic/sonic-dzf-time-measure ]] || exit 125
[[ "$STAGE_DIR" == /data/sonic/时间统计/logs/20260901-233744/* ]] || exit 125

for deb in \
    target/debs/trixie/p4lang-pi_0.1.1-1_amd64.deb \
    target/debs/trixie/p4lang-bmv2_1.15.0-9_amd64.deb \
    target/debs/trixie/p4lang-p4c_1.2.4.2-2_amd64.deb; do
    [[ -f "$deb" ]] || exit 125
done
printf '%s  %s\n' \
    '117b36ebd0b07d034cd2bb319c7f63be692ea4dda90cc9f58d2015bb8ccf2fb8' \
    'src/p4lang/p4lang-p4c_1.2.4.2.orig.tar.gz' | sha256sum -c - \
    > "$PREP_DIR/p4c-source-check.txt" || exit $?

bazel --output_base="$OUTPUT_BASE" clean > "$PREP_DIR/seed-clean.log" 2>&1 || exit $?
[[ ! -e "$ARTIFACT" ]] || exit 125
/usr/bin/time -v -o "$PREP_DIR/seed-time.txt" \
    bazel --output_base="$OUTPUT_BASE" build "${bazel_common[@]}" \
    "$KERNEL_TARGET" "$PI_TARGET" "$BMV2_TARGET" "$P4C_TARGET" "$PI_LAYER_TARGET" \
    > "$PREP_DIR/seed.log" 2>&1 || exit $?

grep -F 'Building Linux kernel' "$PREP_DIR/seed.log" >/dev/null || exit 120
grep -F "p4lang-pi_0.1.1-1_amd64.deb' is up to date" "$PREP_DIR/seed.log" >/dev/null || exit 121
grep -F "p4lang-bmv2_1.15.0-9_amd64.deb' is up to date" "$PREP_DIR/seed.log" >/dev/null || exit 122
grep -F "p4lang-p4c_1.2.4.2-2_amd64.deb' is up to date" "$PREP_DIR/seed.log" >/dev/null || exit 123
[[ ! -e "$ARTIFACT" ]] || exit 125
{
    du -sh "$OUTPUT_BASE" "$OUTPUT_BASE/external" "$REPOSITORY_CACHE"
    stat -c '%n %s' \
        target/debs/trixie/p4lang-pi_0.1.1-1_amd64.deb \
        target/debs/trixie/p4lang-bmv2_1.15.0-9_amd64.deb \
        target/debs/trixie/p4lang-p4c_1.2.4.2-2_amd64.deb
    sha256sum \
        target/debs/trixie/p4lang-pi_0.1.1-1_amd64.deb \
        target/debs/trixie/p4lang-bmv2_1.15.0-9_amd64.deb \
        target/debs/trixie/p4lang-p4c_1.2.4.2-2_amd64.deb
} > "$PREP_DIR/cache-after-seed.txt"
date -Iseconds > "$PREP_DIR/seed-finished.txt"

# Preserve the seeded output/action cache; only restart the server so analysis is cold.
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
    if grep -F 'Building Linux kernel' "$STAGE_DIR/build.log" >/dev/null; then status=124; fi
    if grep -F 'SONiC make (local)' "$STAGE_DIR/build.log" >/dev/null; then status=125; fi
    grep -F 'Build completed successfully' "$STAGE_DIR/build.log" >/dev/null || status=126
fi
printf '%s\n' "$status" > "$STAGE_DIR/runner-status.tmp"
mv "$STAGE_DIR/runner-status.tmp" "$STAGE_DIR/runner-status.txt"
exit "$status"

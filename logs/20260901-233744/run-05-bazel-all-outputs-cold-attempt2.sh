#!/usr/bin/env bash
set -u

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE=05-bazel-all-outputs-cold-attempt2
STAGE_DIR="$RUN_DIR/$STAGE"
MEASURE=/data/sonic/时间统计/measure_sonic_vs.sh
ASCII_ROOT="$REPO/.measure/20260901-233744/bazel-fully-cold-attempt3"
OUTPUT_BASE="$ASCII_ROOT/output-base"
REPOSITORY_CACHE="$ASCII_ROOT/repository-cache"
EVIDENCE="$ASCII_ROOT/evidence-all-outputs-cold-attempt2"
ARTIFACT="$OUTPUT_BASE/execroot/_main/bazel-out/k8-opt/bin/platform/vs/sonic-vs.bin"

clean_p4lang_outputs() {
    rm -f "$REPO"/target/debs/trixie/p4lang-*
    rm -rf \
        "$REPO/src/p4lang/p4lang-pi-0.1.1" \
        "$REPO/src/p4lang/p4lang-bmv2-1.15.0" \
        "$REPO/src/p4lang/p4lang-p4c-1.2.4.2"
    find "$REPO/src/p4lang" -maxdepth 1 -type f \
        \( -name 'p4lang-*.deb' -o -name 'p4lang-*.ddeb' -o -name 'p4lang-*.changes' -o -name 'p4lang-*.buildinfo' \) -delete
}

mkdir -p "$STAGE_DIR" "$EVIDENCE"
cd "$REPO" || exit 125
[[ "$REPO" == /data/sonic/sonic-dzf-time-measure ]] || exit 125
[[ "$STAGE_DIR" == /data/sonic/时间统计/logs/20260901-233744/* ]] || exit 125

{
    du -sh "$OUTPUT_BASE" "$REPOSITORY_CACHE"
    du -sh "$OUTPUT_BASE/external"
    stat -c '%n %s' src/p4lang/*.dsc src/p4lang/*.orig.tar.gz src/p4lang/*.debian.tar.xz
    sha256sum src/p4lang/*.dsc src/p4lang/*.orig.tar.gz src/p4lang/*.debian.tar.xz
} > "$STAGE_DIR/dependencies-before.txt"
printf '%s  %s\n' \
    '117b36ebd0b07d034cd2bb319c7f63be692ea4dda90cc9f58d2015bb8ccf2fb8' \
    'src/p4lang/p4lang-p4c_1.2.4.2.orig.tar.gz' | sha256sum -c - \
    > "$STAGE_DIR/p4c-source-check.txt" || exit $?

bazel --output_base="$OUTPUT_BASE" clean > "$STAGE_DIR/bazel-clean.log" 2>&1 || exit $?
clean_p4lang_outputs
[[ ! -e "$ARTIFACT" ]] || exit 125
compgen -G 'src/p4lang/*.dsc' >/dev/null || exit 125
compgen -G 'src/p4lang/*.orig.tar.gz' >/dev/null || exit 125
compgen -G 'src/p4lang/*.debian.tar.xz' >/dev/null || exit 125
bazel --output_base="$OUTPUT_BASE" shutdown > "$STAGE_DIR/bazel-shutdown.log" 2>&1 || exit $?

RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE" \
    bazel --output_base="$OUTPUT_BASE" build \
    --repository_cache="$REPOSITORY_CACHE" \
    --repository_disable_download \
    --remote_cache= \
    --experimental_remote_downloader= \
    --disk_cache= \
    --action_env=BUILD_SKIP_TEST=y \
    --action_env=HTTP_PROXY=http://127.0.0.1:9 \
    --action_env=HTTPS_PROXY=http://127.0.0.1:9 \
    --action_env=http_proxy=http://127.0.0.1:9 \
    --action_env=https_proxy=http://127.0.0.1:9 \
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
    cp "$REPO"/target/debs/trixie/p4lang-*.deb.log "$STAGE_DIR/" 2>/dev/null || true
    grep -F 'Building Linux kernel' "$STAGE_DIR/build.log" >/dev/null || status=120
    grep -F 'dpkg-buildpackage' "$STAGE_DIR"/p4lang-*.deb.log >/dev/null || status=121
    if grep -E "p4lang-(pi|bmv2|p4c).*is up to date" "$STAGE_DIR/build.log" >/dev/null; then status=122; fi
    if grep -F 'disk cache hit' "$STAGE_DIR/build.log" >/dev/null; then status=123; fi
    if grep -E 'dh_auto_test --no-parallel|(^|[[:space:]])(PASS|FAIL):' "$STAGE_DIR"/p4lang-*.deb.log >/dev/null; then status=124; fi
fi
printf '%s\n' "$status" > "$STAGE_DIR/runner-status.tmp"
mv "$STAGE_DIR/runner-status.tmp" "$STAGE_DIR/runner-status.txt"
exit "$status"

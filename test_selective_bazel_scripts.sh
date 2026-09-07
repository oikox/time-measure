#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/data/sonic/时间统计/logs/20260901-233744
FULL="$ROOT/run-05-bazel-all-outputs-cold-attempt2.sh"
CACHED="$ROOT/run-06-bazel-kernel-p4lang-cached-attempt2.sh"

for script in "$FULL" "$CACHED"; do
    bash -n "$script"
    grep -F -- '--repository_disable_download' "$script" >/dev/null
    grep -F -- '--remote_cache=' "$script" >/dev/null
    grep -F -- '--experimental_remote_downloader=' "$script" >/dev/null
    grep -F -- '--action_env=BUILD_SKIP_TEST=y' "$script" >/dev/null
    grep -F '/data/sonic/sonic-dzf-time-measure' "$script" >/dev/null
    grep -F '/data/sonic/时间统计' "$script" >/dev/null
done

grep -F -- '--disk_cache=' "$FULL" >/dev/null
if grep -F -- '--disk_cache=/data/sonic/时间统计/cache/20260901-233744/bazel-kernel-p4lang' "$FULL" >/dev/null; then
    printf 'full rebuild must not use selective disk cache\n' >&2
    exit 1
fi

grep -F -- '--disk_cache=' "$CACHED" >/dev/null
if grep -F -- '--disk_cache=/data/sonic/时间统计/cache/20260901-233744/bazel-kernel-p4lang' "$CACHED" >/dev/null; then
    printf 'local kernel/p4lang actions cannot use disk cache\n' >&2
    exit 1
fi
grep -F '@sonic_linux_kernel//:kernel_amd64' "$CACHED" >/dev/null
grep -F '@p4lang//:p4lang-pi_0.1.1-1.deb' "$CACHED" >/dev/null
grep -F '@p4lang//:p4lang-bmv2_1.15.0-9.deb' "$CACHED" >/dev/null
grep -F '@p4lang//:p4lang-p4c_1.2.4.2-2.deb' "$CACHED" >/dev/null
grep -F 'seed-finished.txt' "$CACHED" >/dev/null
if [[ $(grep -c 'bazel --output_base="$OUTPUT_BASE" clean' "$CACHED") -ne 1 ]]; then
    printf 'selective cache script must clean exactly once before seeding\n' >&2
    exit 1
fi

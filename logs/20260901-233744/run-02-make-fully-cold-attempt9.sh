#!/usr/bin/env bash
set -u

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE_ROOT="$RUN_DIR/02-make-fully-cold-attempt9"
MEASURE=/data/sonic/时间统计/measure_sonic_vs.sh
COMMON=(PLATFORM=vs NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1 NOBOOKWORM=1 NOTRIXIE=0 ENABLE_DOCKER_BASE_PULL=n SONIC_CONFIG_USE_CCACHE=n SONIC_DPKG_CACHE_METHOD=none SONIC_VERSION_CACHE_METHOD=none)

mkdir -p "$STAGE_ROOT"
finish() {
    local status=$?
    printf '%s\n' "$status" > "$STAGE_ROOT/runner-status.tmp"
    mv "$STAGE_ROOT/runner-status.tmp" "$STAGE_ROOT/runner-status.txt"
    printf '%s\n' "$(date -Iseconds)" > "$STAGE_ROOT/end-to-end-end.txt"
}
trap finish EXIT

cd "$REPO" || exit 125
printf '%s\n' "$(date -Iseconds)" > "$STAGE_ROOT/end-to-end-start.txt"
git status --short --branch > "$STAGE_ROOT/git-before.txt"
git submodule status --recursive >> "$STAGE_ROOT/git-before.txt"
docker images --format '{{.ID}}\t{{.Repository}}:{{.Tag}}\t{{.Size}}' > "$STAGE_ROOT/docker-images-before.txt"
docker system df > "$STAGE_ROOT/docker-system-before.txt"
[[ ! -e target ]] || exit 125

RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed 02-make-fully-cold-attempt9-init make init
status=$?
if (( status != 0 )); then exit "$status"; fi
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed 02-make-fully-cold-attempt9-configure make "${COMMON[@]}" configure
status=$?
if (( status != 0 )); then exit "$status"; fi

mapfile -t TAGS < <(BLDENV=trixie make -s -f Makefile.work "${COMMON[@]}" showtag | grep '^sonic-slave')
if (( ${#TAGS[@]} != 2 )); then exit 125; fi
printf 'user_image=%s\nbase_image=%s\n' "${TAGS[0]}" "${TAGS[1]}" > "$STAGE_ROOT/slave-images.txt"
docker image inspect "${TAGS[0]}" > "$STAGE_ROOT/user-image-after-configure.json"
docker image inspect "${TAGS[1]}" > "$STAGE_ROOT/base-image-after-configure.json"
docker system df > "$STAGE_ROOT/docker-system-after-configure.txt"

RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed 02-make-fully-cold-attempt9-build make "${COMMON[@]}" GOPROXY=https://goproxy.cn,direct target/sonic-vs.bin
exit $?

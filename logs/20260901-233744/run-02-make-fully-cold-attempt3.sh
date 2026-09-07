#!/usr/bin/env bash
set -u

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE_ROOT="$RUN_DIR/02-make-fully-cold-attempt3"
MEASURE=/data/sonic/时间统计/measure_sonic_vs.sh
COMMON=(PLATFORM=vs NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1 NOBOOKWORM=1 NOTRIXIE=0 ENABLE_DOCKER_BASE_PULL=n SONIC_CONFIG_USE_CCACHE=n SONIC_DPKG_CACHE_METHOD=none SONIC_VERSION_CACHE_METHOD=none)

mkdir -p "$STAGE_ROOT"
cd "$REPO" || exit 125
printf '%s\n' "$(date -Iseconds)" > "$STAGE_ROOT/end-to-end-start.txt"
git status --short --branch > "$STAGE_ROOT/git-before.txt"
git submodule status --recursive >> "$STAGE_ROOT/git-before.txt"
docker images --format '{{.ID}}\t{{.Repository}}:{{.Tag}}\t{{.Size}}' > "$STAGE_ROOT/docker-images-before.txt"
docker system df > "$STAGE_ROOT/docker-system-before.txt"

TARGET_REAL=$(realpath -m "$REPO/target")
if [[ "$TARGET_REAL" != "$REPO/target" ]]; then exit 125; fi
rm -rf "$TARGET_REAL"

RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed 02-make-fully-cold-attempt3-init make init
status=$?
if (( status != 0 )); then exit "$status"; fi
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed 02-make-fully-cold-attempt3-configure make "${COMMON[@]}" configure
status=$?
if (( status != 0 )); then exit "$status"; fi

mapfile -t TAGS < <(BLDENV=trixie make -s -f Makefile.work "${COMMON[@]}" showtag | grep '^sonic-slave')
if (( ${#TAGS[@]} != 2 )); then exit 125; fi
USER_IMAGE=${TAGS[0]}
BASE_IMAGE=${TAGS[1]}
printf 'user_image=%s\nbase_image=%s\n' "$USER_IMAGE" "$BASE_IMAGE" > "$STAGE_ROOT/slave-images.txt"
docker image inspect "$USER_IMAGE" > "$STAGE_ROOT/user-image-before-remove.json" 2>/dev/null || true
docker image inspect "$BASE_IMAGE" > "$STAGE_ROOT/base-image-before-remove.json" 2>/dev/null || true
docker image rm -f "$USER_IMAGE" >> "$STAGE_ROOT/docker-cleanup.log" 2>&1 || true
docker image rm -f "$BASE_IMAGE" >> "$STAGE_ROOT/docker-cleanup.log" 2>&1 || true
docker builder prune -af >> "$STAGE_ROOT/docker-cleanup.log" 2>&1
docker image inspect "$USER_IMAGE" >/dev/null 2>&1 && exit 125 || true
docker image inspect "$BASE_IMAGE" >/dev/null 2>&1 && exit 125 || true
docker system df > "$STAGE_ROOT/docker-system-after-cleanup.txt"

RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed 02-make-fully-cold-attempt3-build make "${COMMON[@]}" GOPROXY=https://goproxy.cn,direct target/sonic-vs.bin
status=$?
printf '%s\n' "$status" > "$STAGE_ROOT/runner-status.tmp"
mv "$STAGE_ROOT/runner-status.tmp" "$STAGE_ROOT/runner-status.txt"
printf '%s\n' "$(date -Iseconds)" > "$STAGE_ROOT/end-to-end-end.txt"
exit "$status"

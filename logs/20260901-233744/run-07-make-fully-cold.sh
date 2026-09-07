#!/usr/bin/env bash
set -Eeuo pipefail

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE=07-make-fully-cold
STAGE_ROOT="$RUN_DIR/$STAGE"
MEASURE=/data/sonic/时间统计/measure_sonic_vs.sh
SCRIPT=$(realpath "$0")
COMMON=(PLATFORM=vs NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1 NOBOOKWORM=1 NOTRIXIE=0 ENABLE_DOCKER_BASE_PULL=n SONIC_CONFIG_USE_CCACHE=n SONIC_DPKG_CACHE_METHOD=none SONIC_VERSION_CACHE_METHOD=none BUILD_SKIP_TEST=y SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=192)

validate_paths() {
    [[ "$(realpath -m "$REPO")" == "$REPO" ]] || exit 125
    [[ "$(realpath -m "$RUN_DIR")" == /data/sonic/时间统计/logs/* ]] || exit 125
    [[ "$(realpath -m "$STAGE_ROOT")" == "$RUN_DIR/$STAGE" ]] || exit 125
    [[ "$REPO" != /data/sonic/sonic-dzf ]] || exit 125
}

run_stages() {
    cd "$REPO"
    RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE-init" \
        make "${COMMON[@]}" init
    RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE-configure" \
        make "${COMMON[@]}" configure

    mapfile -t tags < <(BLDENV=trixie make -s -f Makefile.work "${COMMON[@]}" showtag | grep '^sonic-slave')
    (( ${#tags[@]} == 2 )) || exit 125
    docker image inspect "${tags[0]}" > "$STAGE_ROOT/user-image-after-configure.json"
    docker image inspect "${tags[1]}" > "$STAGE_ROOT/base-image-after-configure.json"
    docker system df > "$STAGE_ROOT/docker-system-after-configure.txt"

    RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE-build" \
        make "${COMMON[@]}" GOPROXY=https://goproxy.cn,direct target/sonic-vs.bin
    RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" verify-artifact "$STAGE" \
        "$REPO/target/sonic-vs.bin"
}

validate_paths
if [[ "${1:-}" == --run-stages ]]; then
    run_stages
    exit 0
fi

mkdir -p "$STAGE_ROOT"
exec 9>"$RUN_DIR/make-measurement.lock"
flock -n 9 || {
    printf 'another Make measurement is running\n' >&2
    exit 124
}

rm -rf "$STAGE_ROOT"
mkdir -p "$STAGE_ROOT"
finish() {
    local status=$?
    printf '%s\n' "$status" > "$STAGE_ROOT/runner-status.tmp"
    mv "$STAGE_ROOT/runner-status.tmp" "$STAGE_ROOT/runner-status.txt"
    date -Iseconds > "$STAGE_ROOT/end-to-end-end.txt"
}
trap finish EXIT

cd "$REPO"
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" record-environment "$STAGE"
git status --short --branch > "$STAGE_ROOT/git-before.txt"
git submodule status --recursive >> "$STAGE_ROOT/git-before.txt"
docker images --format '{{.ID}}\t{{.Repository}}:{{.Tag}}\t{{.Size}}' > "$STAGE_ROOT/docker-images-before.txt"
docker system df > "$STAGE_ROOT/docker-system-before.txt"

mapfile -t TAGS < <(BLDENV=trixie make -s -f Makefile.work "${COMMON[@]}" showtag | grep '^sonic-slave')
(( ${#TAGS[@]} == 2 )) || {
    printf 'unable to resolve exact slave image tags\n' >&2
    exit 125
}
printf 'user_image=%s\nbase_image=%s\n' "${TAGS[0]}" "${TAGS[1]}" > "$STAGE_ROOT/slave-images.txt"
docker image inspect "${TAGS[0]}" > "$STAGE_ROOT/user-image-before-remove.json" 2>/dev/null || true
docker image inspect "${TAGS[1]}" > "$STAGE_ROOT/base-image-before-remove.json" 2>/dev/null || true

git clean -ndX -- . ':(exclude).measure' ':(exclude).alinos' > "$STAGE_ROOT/root-clean-preview.txt"
git submodule foreach --recursive 'git clean -ndX' > "$STAGE_ROOT/submodule-clean-preview.txt" 2>&1
docker run --rm --network none --userns=host --user 0:0 --entrypoint /bin/bash -v "$REPO:/repo" "${TAGS[0]}" \
    -c 'rm -rf -- /repo/fsroot-vs /repo/fsroot.docker.* /repo/dpkg /repo/target' \
    > "$STAGE_ROOT/root-owned-clean.log" 2>&1
git clean -fdX -- . ':(exclude).measure' ':(exclude).alinos' > "$STAGE_ROOT/root-clean.log" 2>&1
git submodule foreach --recursive 'git clean -fdX' > "$STAGE_ROOT/submodule-clean.log" 2>&1

[[ ! -e target ]] || exit 125
[[ ! -e dpkg ]] || exit 125
[[ ! -e fsroot-vs ]] || exit 125

docker image rm -f "${TAGS[0]}" >> "$STAGE_ROOT/docker-cleanup.log" 2>&1 || true
docker image rm -f "${TAGS[1]}" >> "$STAGE_ROOT/docker-cleanup.log" 2>&1 || true
docker builder prune -af >> "$STAGE_ROOT/docker-cleanup.log" 2>&1
docker image inspect "${TAGS[0]}" > "$STAGE_ROOT/user-image-after-remove.json" 2>/dev/null && exit 125 || true
docker image inspect "${TAGS[1]}" > "$STAGE_ROOT/base-image-after-remove.json" 2>/dev/null && exit 125 || true
docker system df > "$STAGE_ROOT/docker-system-after-cleanup.txt"

date -Iseconds > "$STAGE_ROOT/end-to-end-start.txt"
if /usr/bin/time -v -o "$STAGE_ROOT/end-to-end-time.txt" "$SCRIPT" --run-stages \
    > "$STAGE_ROOT/end-to-end.log" 2>&1; then
    exit 0
else
    exit $?
fi

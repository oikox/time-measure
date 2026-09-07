#!/usr/bin/env bash
set -Eeuo pipefail

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE=08-make-deps-retained-offline
STAGE_ROOT="$RUN_DIR/$STAGE"
MEASURE=/data/sonic/时间统计/measure_sonic_vs.sh
SCRIPT=$(realpath "$0")
COLD_SLAVE_IMAGES="$RUN_DIR/07-make-fully-cold/slave-images.txt"
VERSION_CACHE="$CACHE_ROOT/make-version-cache"
FIPS_CACHE="$CACHE_ROOT/make-fips-cache"
CARGO_HOME_CACHE="$CACHE_ROOT/make-cargo-home"
RUSTUP_HOME_CACHE="$CACHE_ROOT/make-rustup-home"
GO_MOD_CACHE="$CACHE_ROOT/make-go-mod-cache"
GO_SUMDB_CACHE="$CACHE_ROOT/make-go-sumdb-cache"
PIP_WHEELHOUSE="$CACHE_ROOT/make-pip-wheelhouse"
GIT_MIRROR_ROOT="$CACHE_ROOT/make-git-mirrors"
GIT_CONFIG="$CACHE_ROOT/offline.gitconfig"
DEBOOTSTRAP_CACHE="$CACHE_ROOT/make-debootstrap-cache"
ROOTFS_APT_CACHE="$CACHE_ROOT/make-rootfs-apt-cache"
DEBOOTSTRAP_TARBALL="$DEBOOTSTRAP_CACHE/baseimage-amd64-trixie.tgz"
SONIC_DEBOOTSTRAP_TARBALL=/rootfs-cache/make-debootstrap-cache/baseimage-amd64-trixie.tgz
SONIC_ROOTFS_APT_CACHE=/rootfs-cache/make-rootfs-apt-cache
SONIC_ROOTFS_DOCKER_GPG_KEY="$SONIC_ROOTFS_APT_CACHE/docker.asc"
BUILDER_EXTRA="-v $GIT_MIRROR_ROOT:/git-mirrors:ro -v $GIT_CONFIG:/etc/sonic-offline.gitconfig:ro -v $CARGO_HOME_CACHE:/cargo-home:rw -v $RUSTUP_HOME_CACHE:/rustup-home:ro -v $GO_MOD_CACHE:/tmp/go/pkg/mod:rw -v $GO_SUMDB_CACHE:/tmp/go/pkg/sumdb:rw -v $PIP_WHEELHOUSE:/pip-wheelhouse:ro -v $CACHE_ROOT:/rootfs-cache:ro -e GIT_CONFIG_GLOBAL=/etc/sonic-offline.gitconfig -e GIT_TERMINAL_PROMPT=0 -e CARGO_HOME=/cargo-home -e CARGO_NET_OFFLINE=true -e GOMODCACHE=/tmp/go/pkg/mod -e DEB_BUILD_OPTIONS=nocheck -e PIP_NO_INDEX=1 -e PIP_FIND_LINKS=/pip-wheelhouse -e SONIC_DEBOOTSTRAP_TARBALL=$SONIC_DEBOOTSTRAP_TARBALL -e SONIC_ROOTFS_APT_CACHE=$SONIC_ROOTFS_APT_CACHE -e SONIC_ROOTFS_DOCKER_GPG_KEY=$SONIC_ROOTFS_DOCKER_GPG_KEY -e SONIC_ROOTFS_PIP_WHEELHOUSE=/pip-wheelhouse -e SONIC_ROOTFS_OFFLINE=y"
COMMON=(PLATFORM=vs NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1 NOBOOKWORM=1 NOTRIXIE=0 ENABLE_DOCKER_BASE_PULL=n SONIC_CONFIG_USE_CCACHE=n SONIC_DPKG_CACHE_METHOD=none SONIC_VERSION_CACHE_METHOD=rcache SONIC_VERSION_CACHE_SOURCE=$VERSION_CACHE BUILD_SKIP_TEST=y SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=192 TRUSTED_GPG_URLS=)
OFFLINE_ENV=(http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9 no_proxy=localhost,127.0.0.1,0.0.0.0 NO_PROXY=localhost,127.0.0.1,0.0.0.0 GOPROXY=off CARGO_NET_OFFLINE=true npm_config_offline=true PIP_NO_INDEX=1 GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false "SONIC_BUILDER_EXTRA_CMDLINE=$BUILDER_EXTRA")
HOOK_PACKAGE="$REPO/src/sonic-build-hooks/buildinfo/sonic-build-hooks_1.0_all.deb"
HOOK_BACKUP="$STAGE_ROOT/retained-sonic-build-hooks_1.0_all.deb"

validate_paths() {
    [[ "$(realpath -m "$REPO")" == "$REPO" ]] || exit 125
    [[ "$(realpath -m "$RUN_DIR")" == /data/sonic/时间统计/logs/* ]] || exit 125
    [[ "$(realpath -m "$STAGE_ROOT")" == "$RUN_DIR/$STAGE" ]] || exit 125
    [[ "$REPO" != /data/sonic/sonic-dzf ]] || exit 125
}

load_retained_tags() {
    USER_IMAGE=
    BASE_IMAGE=
    while IFS='=' read -r key value; do
        case "$key" in
            user_image) USER_IMAGE=$value ;;
            base_image) BASE_IMAGE=$value ;;
        esac
    done < "$COLD_SLAVE_IMAGES"
    [[ "$USER_IMAGE" == sonic-slave-* && "$BASE_IMAGE" == sonic-slave-* ]] || exit 125
}

prepare_dependency_caches() {
    docker run --rm --network none --userns=host --user 0:0 --entrypoint /bin/bash \
        -v "$VERSION_CACHE:/cache" -v "$CARGO_HOME_CACHE:/cargo-home" -v "$GO_MOD_CACHE:/tmp/go/pkg/mod" -v "$GO_SUMDB_CACHE:/tmp/go/pkg/sumdb" "$USER_IMAGE" \
        -c 'mkdir -p /cache/sonic-slave-trixie/web /cache/sonic-slave-trixie/pip /cargo-home /tmp/go/pkg/mod /tmp/go/pkg/sumdb; chmod -R a+rwx /cache /cargo-home /tmp/go/pkg/mod /tmp/go/pkg/sumdb'
}

restore_fips_cache() {
    mkdir -p "$REPO/target/debs/trixie"
    cp -f "$FIPS_CACHE"/*.deb "$REPO/target/debs/trixie/"
    [[ "$(find "$REPO/target/debs/trixie" -maxdepth 1 -type f \( -name '*+fips*.deb' -o -name 'symcrypt-openssl_*.deb' \) | wc -l)" -eq 27 ]] || exit 125
}

vcache_inventory() {
    local output=$1
    (
        cd "$REPO/target/vcache"
        find . -type d -printf 'd %p\n'
        find . -type l -printf 'l %p %l\n'
        find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
    ) | LC_ALL=C sort > "$output"
}

compiled_output_inventory() {
    local output=$1
    {
        find target/debs target/python-wheels -type f -printf '%p %s bytes\n' 2>/dev/null || true
        find target -maxdepth 1 -type f -name 'docker-*.gz' -printf '%p %s bytes\n' 2>/dev/null || true
        for path in fsroot-vs target/sonic-vs.bin__vs__rfs.squashfs target/sonic-vs.bin; do
            [[ ! -e "$path" ]] || stat -c '%n %s bytes' "$path"
        done
    } | LC_ALL=C sort > "$output"
}

clear_compiled_outputs() {
    docker run --rm --network none --userns=host --user 0:0 --entrypoint /bin/bash \
        -v "$REPO:/repo" "$USER_IMAGE" \
        -c 'rm -rf -- /repo/fsroot-vs /repo/target/debs /repo/target/python-wheels'
    find target -maxdepth 1 -type f -name 'docker-*.gz' -delete
    rm -f target/sonic-vs.bin__vs__rfs.squashfs target/sonic-vs.bin
}

refresh_retained_outputs() {
    local timestamp="$STAGE_ROOT/retained-output.timestamp"
    touch "$timestamp"
    find target -type f \
        ! -path 'target/vcache/*' \
        ! -path 'target/debs/*' \
        ! -path 'target/python-wheels/*' \
        ! -name 'docker-*.gz' \
        ! -path 'target/sonic-vs.bin' \
        ! -path 'target/sonic-vs.bin__vs__rfs.squashfs' \
        -exec touch -c -r "$timestamp" {} +
}

run_build() {
    cd "$REPO"
    restore_fips_cache
    refresh_retained_outputs
    env "${OFFLINE_ENV[@]}" BLDENV=trixie make -f Makefile.work MAKEFLAGS= "${COMMON[@]}" target/sonic-vs.bin
}

run_stages() {
    cd "$REPO"
    RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE-init" \
        env "${OFFLINE_ENV[@]}" make "${COMMON[@]}" init
    RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE-configure" \
        env "${OFFLINE_ENV[@]}" make "${COMMON[@]}" configure

    load_retained_tags
    docker image inspect "$USER_IMAGE" > "$STAGE_ROOT/user-image-after-configure.json"
    docker image inspect "$BASE_IMAGE" > "$STAGE_ROOT/base-image-after-configure.json"

    RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE-build" \
        "$SCRIPT" --run-build
    RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" verify-artifact "$STAGE" \
        "$REPO/target/sonic-vs.bin"
}

validate_paths
[[ "$(realpath -m "$CARGO_HOME_CACHE")" == "$CACHE_ROOT/make-cargo-home" ]] || exit 125
[[ "$(realpath -m "$RUSTUP_HOME_CACHE")" == "$CACHE_ROOT/make-rustup-home" ]] || exit 125
[[ "$(realpath -m "$GO_MOD_CACHE")" == "$CACHE_ROOT/make-go-mod-cache" ]] || exit 125
[[ "$(realpath -m "$GO_SUMDB_CACHE")" == "$CACHE_ROOT/make-go-sumdb-cache" ]] || exit 125
[[ "$(realpath -m "$PIP_WHEELHOUSE")" == "$CACHE_ROOT/make-pip-wheelhouse" ]] || exit 125
[[ "$(realpath -m "$DEBOOTSTRAP_CACHE")" == "$CACHE_ROOT/make-debootstrap-cache" ]] || exit 125
[[ "$(realpath -m "$ROOTFS_APT_CACHE")" == "$CACHE_ROOT/make-rootfs-apt-cache" ]] || exit 125
[[ -s "$DEBOOTSTRAP_TARBALL" && -f "$DEBOOTSTRAP_TARBALL.metadata" ]] || {
    printf 'retained debootstrap input is incomplete: %s\n' "$DEBOOTSTRAP_CACHE" >&2
    exit 125
}
grep -qx 'arch=amd64' "$DEBOOTSTRAP_TARBALL.metadata" || exit 125
grep -qx 'distro=trixie' "$DEBOOTSTRAP_TARBALL.metadata" || exit 125
[[ -s "$ROOTFS_APT_CACHE/cache.tgz" && -s "$ROOTFS_APT_CACHE/docker.asc" ]] || {
    printf 'retained rootfs APT input is incomplete: %s\n' "$ROOTFS_APT_CACHE" >&2
    exit 125
}
[[ "$(find "$ROOTFS_APT_CACHE/extra-debs" -type f -name '*eatmydata*.deb' 2>/dev/null | wc -l)" -eq 2 ]] || {
    printf 'retained early rootfs APT inputs are incomplete: %s\n' "$ROOTFS_APT_CACHE/extra-debs" >&2
    exit 125
}
[[ -n "$(find "$VERSION_CACHE" -type f -print -quit 2>/dev/null)" ]] || {
    printf 'dedicated Make version cache is empty: %s\n' "$VERSION_CACHE" >&2
    exit 125
}
[[ -n "$(find "$CARGO_HOME_CACHE" -type f -print -quit 2>/dev/null)" ]] || {
    printf 'dedicated Cargo home is empty: %s\n' "$CARGO_HOME_CACHE" >&2
    exit 125
}
[[ -x "$RUSTUP_HOME_CACHE/bin/rustc" && -n "$(find "$RUSTUP_HOME_CACHE/registry" -type f -print -quit 2>/dev/null)" ]] || {
    printf 'fixed Rust toolchain cache is incomplete: %s\n' "$RUSTUP_HOME_CACHE" >&2
    exit 125
}
[[ -n "$(find "$GO_MOD_CACHE" -type f -print -quit 2>/dev/null)" ]] || {
    printf 'dedicated Go module cache is empty: %s\n' "$GO_MOD_CACHE" >&2
    exit 125
}
[[ -n "$(find "$GO_SUMDB_CACHE" -type f -print -quit 2>/dev/null)" ]] || {
    printf 'dedicated Go checksum database cache is empty: %s\n' "$GO_SUMDB_CACHE" >&2
    exit 125
}
[[ -n "$(find "$PIP_WHEELHOUSE" -type f -print -quit 2>/dev/null)" ]] || {
    printf 'dedicated pip wheelhouse is empty: %s\n' "$PIP_WHEELHOUSE" >&2
    exit 125
}
[[ "$(find "$FIPS_CACHE" -type f -name '*.deb' 2>/dev/null | wc -l)" -eq 27 ]] || {
    printf 'retained FIPS dependency set is incomplete: %s\n' "$FIPS_CACHE" >&2
    exit 125
}
find "$FIPS_CACHE" -type f -name '*.deb' -size 0 -print -quit | grep -q . && exit 125 || true
[[ -f "$GIT_CONFIG" && "$(grep -c 'insteadOf =' "$GIT_CONFIG")" -eq 17 ]] || {
    printf 'offline Git rewrite configuration is incomplete: %s\n' "$GIT_CONFIG" >&2
    exit 125
}
[[ "$(find "$GIT_MIRROR_ROOT" -type d -name objects | wc -l)" -eq 17 ]] || {
    printf 'offline Git mirror set is incomplete: %s\n' "$GIT_MIRROR_ROOT" >&2
    exit 125
}
if [[ "${1:-}" == --run-build ]]; then
    run_build
    exit 0
fi
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
git status --short --branch > "$STAGE_ROOT/git-before-clean.txt"
git submodule status --recursive >> "$STAGE_ROOT/git-before-clean.txt"
docker images --format '{{.ID}}\t{{.Repository}}:{{.Tag}}\t{{.Size}}' > "$STAGE_ROOT/docker-images-before-clean.txt"
docker system df > "$STAGE_ROOT/docker-system-before-clean.txt"
du -sh target target/vcache > "$STAGE_ROOT/cache-before-clean.txt"
[[ -d target/vcache ]] || exit 125

load_retained_tags
printf 'user_image=%s\nbase_image=%s\n' "$USER_IMAGE" "$BASE_IMAGE" > "$STAGE_ROOT/slave-images.txt"
docker image inspect "$USER_IMAGE" > "$STAGE_ROOT/user-image-retained.json"
docker image inspect "$BASE_IMAGE" > "$STAGE_ROOT/base-image-retained.json"
prepare_dependency_caches
[[ -f "$HOOK_PACKAGE" ]] || {
    printf 'retained sonic-build-hooks package missing: %s\n' "$HOOK_PACKAGE" >&2
    exit 125
}
cp -a "$HOOK_PACKAGE" "$HOOK_BACKUP"
sha256sum "$HOOK_PACKAGE" > "$STAGE_ROOT/sonic-build-hooks-before-clean.sha256"
vcache_inventory "$STAGE_ROOT/vcache-before-clean.sha256"
compiled_output_inventory "$STAGE_ROOT/compiled-outputs-before-clean.txt"

clear_compiled_outputs
prepare_dependency_caches
sha256sum "$HOOK_PACKAGE" > "$STAGE_ROOT/sonic-build-hooks-after-clean.sha256"
[[ "$(sha256sum "$HOOK_BACKUP" | cut -d' ' -f1)" == "$(sha256sum "$HOOK_PACKAGE" | cut -d' ' -f1)" ]] || exit 125
[[ -d target/vcache ]] || {
    printf 'target/vcache missing after product clean\n' >&2
    exit 125
}
vcache_inventory "$STAGE_ROOT/vcache-after-clean.sha256"
cmp -s "$STAGE_ROOT/vcache-before-clean.sha256" "$STAGE_ROOT/vcache-after-clean.sha256" || {
    printf 'target/vcache changed during product clean\n' >&2
    diff -u "$STAGE_ROOT/vcache-before-clean.sha256" "$STAGE_ROOT/vcache-after-clean.sha256" > "$STAGE_ROOT/vcache-clean.diff" || true
    exit 125
}
compiled_output_inventory "$STAGE_ROOT/compiled-outputs-after-clean.txt"
[[ ! -s "$STAGE_ROOT/compiled-outputs-after-clean.txt" ]] || exit 125
[[ ! -e "$REPO/fsroot-vs" ]] || exit 125
[[ ! -e target/debs ]] || exit 125
[[ ! -e target/python-wheels ]] || exit 125
[[ -z "$(find target -maxdepth 1 -type f -name 'docker-*.gz' -print -quit)" ]] || exit 125
[[ ! -e target/sonic-vs.bin__vs__rfs.squashfs ]] || exit 125
[[ ! -e target/sonic-vs.bin ]] || exit 125
docker image inspect "$USER_IMAGE" > "$STAGE_ROOT/user-image-after-clean.json"
docker image inspect "$BASE_IMAGE" > "$STAGE_ROOT/base-image-after-clean.json"
du -sh target target/vcache > "$STAGE_ROOT/cache-after-clean.txt"
{
    du -sh "$DEBOOTSTRAP_CACHE" "$ROOTFS_APT_CACHE"
    stat -c '%n %s bytes %y' "$DEBOOTSTRAP_TARBALL" "$DEBOOTSTRAP_TARBALL.metadata" "$ROOTFS_APT_CACHE/cache.tgz" "$ROOTFS_APT_CACHE/docker.asc"
    sha256sum "$DEBOOTSTRAP_TARBALL" "$DEBOOTSTRAP_TARBALL.metadata" "$ROOTFS_APT_CACHE/cache.tgz" "$ROOTFS_APT_CACHE/docker.asc"
    find "$ROOTFS_APT_CACHE/extra-debs" -type f -name '*.deb' -exec sha256sum {} +
} > "$STAGE_ROOT/rootfs-cache-inventory.txt"
docker system df > "$STAGE_ROOT/docker-system-after-clean.txt"
printf '%s\n' "${OFFLINE_ENV[@]}" > "$STAGE_ROOT/network-policy.txt"

date -Iseconds > "$STAGE_ROOT/end-to-end-start.txt"
if /usr/bin/time -v -o "$STAGE_ROOT/end-to-end-time.txt" "$SCRIPT" --run-stages \
    > "$STAGE_ROOT/end-to-end.log" 2>&1; then
    exit 0
else
    exit $?
fi

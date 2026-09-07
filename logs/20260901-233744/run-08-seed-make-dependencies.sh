#!/usr/bin/env bash
set -Eeuo pipefail

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE=08-make-deps-retained-offline-seed
STAGE_ROOT="$RUN_DIR/$STAGE"
MEASURE=/data/sonic/时间统计/measure_sonic_vs.sh
VERSION_CACHE="$CACHE_ROOT/make-version-cache"
FIPS_CACHE="$CACHE_ROOT/make-fips-cache"
CARGO_HOME_CACHE="$CACHE_ROOT/make-cargo-home"
RUSTUP_HOME_CACHE="$CACHE_ROOT/make-rustup-home"
GO_MOD_CACHE="$CACHE_ROOT/make-go-mod-cache"
GO_SUMDB_CACHE="$CACHE_ROOT/make-go-sumdb-cache"
GIT_MIRROR_ROOT="$CACHE_ROOT/make-git-mirrors"
GIT_CONFIG="$CACHE_ROOT/offline.gitconfig"
DEBOOTSTRAP_CACHE="$CACHE_ROOT/make-debootstrap-cache"
ROOTFS_APT_CACHE="$CACHE_ROOT/make-rootfs-apt-cache"
DEBOOTSTRAP_TARBALL="$DEBOOTSTRAP_CACHE/baseimage-amd64-trixie.tgz"
SONIC_DEBOOTSTRAP_TARBALL=/rootfs-cache/make-debootstrap-cache/baseimage-amd64-trixie.tgz
SONIC_ROOTFS_APT_CACHE=/rootfs-cache/make-rootfs-apt-cache
SONIC_ROOTFS_DOCKER_GPG_KEY="$SONIC_ROOTFS_APT_CACHE/docker.asc"
COLD_SLAVE_IMAGES="$RUN_DIR/07-make-fully-cold/slave-images.txt"
BUILDER_EXTRA="-v $GIT_MIRROR_ROOT:/git-mirrors:ro -v $GIT_CONFIG:/etc/sonic-offline.gitconfig:ro -v $CARGO_HOME_CACHE:/cargo-home:rw -v $RUSTUP_HOME_CACHE:/rustup-home:rw -v $GO_MOD_CACHE:/tmp/go/pkg/mod:rw -v $GO_SUMDB_CACHE:/tmp/go/pkg/sumdb:rw -v $CACHE_ROOT:/rootfs-cache:rw -e GIT_CONFIG_GLOBAL=/etc/sonic-offline.gitconfig -e GIT_TERMINAL_PROMPT=0 -e CARGO_HOME=/cargo-home -e GOMODCACHE=/tmp/go/pkg/mod -e DEB_BUILD_OPTIONS=nocheck -e SONIC_DEBOOTSTRAP_TARBALL=$SONIC_DEBOOTSTRAP_TARBALL -e SONIC_ROOTFS_APT_CACHE=$SONIC_ROOTFS_APT_CACHE -e SONIC_ROOTFS_DOCKER_GPG_KEY=$SONIC_ROOTFS_DOCKER_GPG_KEY"
SEED_ENV=("SONIC_BUILDER_EXTRA_CMDLINE=$BUILDER_EXTRA")
COMMON=(PLATFORM=vs NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1 NOBOOKWORM=1 NOTRIXIE=0 ENABLE_DOCKER_BASE_PULL=n SONIC_CONFIG_USE_CCACHE=n SONIC_DPKG_CACHE_METHOD=none SONIC_VERSION_CACHE_METHOD=cache SONIC_VERSION_CACHE_SOURCE=$VERSION_CACHE BUILD_SKIP_TEST=y SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=192 TRUSTED_GPG_URLS=)

prepare_dependency_caches() {
    local user_image
    user_image=$(grep '^user_image=' "$COLD_SLAVE_IMAGES" | cut -d= -f2-)
    [[ "$user_image" == sonic-slave-* ]] || exit 125
    docker run --rm --network none --userns=host --user 0:0 --entrypoint /bin/bash \
        -v "$VERSION_CACHE:/cache" -v "$CARGO_HOME_CACHE:/cargo-home" -v "$GO_MOD_CACHE:/tmp/go/pkg/mod" -v "$GO_SUMDB_CACHE:/tmp/go/pkg/sumdb" "$user_image" \
        -c 'mkdir -p /cache/sonic-slave-trixie/web /cache/sonic-slave-trixie/pip /cargo-home /tmp/go/pkg/mod /tmp/go/pkg/sumdb; chmod -R a+rwx /cache /cargo-home /tmp/go/pkg/mod /tmp/go/pkg/sumdb'
}

seed_debootstrap_cache() {
    local user_image
    user_image=$(grep '^user_image=' "$COLD_SLAVE_IMAGES" | cut -d= -f2-)
    [[ "$user_image" == sonic-slave-* ]] || exit 125
    rm -f "$DEBOOTSTRAP_TARBALL" "$DEBOOTSTRAP_TARBALL.metadata"
    docker run --rm --userns=host --user 0:0 --entrypoint /bin/bash \
        -v "$DEBOOTSTRAP_CACHE:/debootstrap-cache:rw" "$user_image" \
        -c 'rm -rf /tmp/debootstrap-root; SKIP_BUILD_HOOK=y debootstrap --variant=minbase --arch amd64 --make-tarball=/debootstrap-cache/baseimage-amd64-trixie.tgz trixie /tmp/debootstrap-root http://deb.debian.org/debian; chmod a+r /debootstrap-cache/baseimage-amd64-trixie.tgz'
    printf 'arch=amd64\ndistro=trixie\n' > "$DEBOOTSTRAP_TARBALL.metadata.tmp"
    mv "$DEBOOTSTRAP_TARBALL.metadata.tmp" "$DEBOOTSTRAP_TARBALL.metadata"
    [[ -s "$DEBOOTSTRAP_TARBALL" ]]
}

seed_multistage_watchdog_apt_caches() {
    local source_cache target_cache version_sha image
    source_cache=$(find "$VERSION_CACHE/docker-config-engine-trixie" -maxdepth 1 -type f -name '*.tgz' -size +1048576c -print -quit)
    [[ -n "$source_cache" ]] || exit 125
    for image in docker-bmp-watchdog docker-gnmi-watchdog; do
        version_sha=$( (cat "$REPO/dockers/$image/Dockerfile.j2"; cat "$REPO"/files/build/versions/dockers/$image/versions-*-trixie-amd64 "$REPO"/files/build/versions/default/versions-* 2>/dev/null) | sha1sum | cut -c1-23)
        target_cache="$VERSION_CACHE/$image/$image-$version_sha.tgz"
        mkdir -p "$(dirname "$target_cache")"
        cp -f "$source_cache" "$target_cache.tmp"
        mv "$target_cache.tmp" "$target_cache"
    done
}

seed_watchdog_rust_dependencies() {
    local user_image
    user_image=$(grep '^user_image=' "$COLD_SLAVE_IMAGES" | cut -d= -f2-)
    [[ "$user_image" == sonic-slave-* ]] || exit 125
    docker run --rm --userns=host --user 0:0 --entrypoint /bin/bash \
        -v "$RUSTUP_HOME_CACHE:/rustup-home:rw" \
        -v "$REPO/dockers/docker-bmp-watchdog/watchdog:/bmp-watchdog:ro" \
        -v "$REPO/dockers/docker-gnmi-watchdog/watchdog:/gnmi-watchdog:ro" \
        "$user_image" -c '
            if [ ! -x /rustup-home/bin/rustc ]; then
                /usr/bin/curl --proto "=https" -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh
                RUSTUP_HOME=/rustup-home CARGO_HOME=/rustup-home sh /tmp/rustup-init.sh --default-toolchain 1.79.0 -y
            fi
            RUSTUP_HOME=/rustup-home CARGO_HOME=/rustup-home /rustup-home/bin/cargo fetch --locked --manifest-path /bmp-watchdog/Cargo.toml
            RUSTUP_HOME=/rustup-home CARGO_HOME=/rustup-home /rustup-home/bin/cargo fetch --locked --manifest-path /gnmi-watchdog/Cargo.toml
            chmod -R a+rX /rustup-home
        '
    [[ -x "$RUSTUP_HOME_CACHE/bin/rustc" ]]
    [[ -n "$(find "$RUSTUP_HOME_CACHE/registry" -type f -print -quit)" ]]
}

[[ "$(realpath -m "$REPO")" == "$REPO" ]] || exit 125
[[ "$(realpath -m "$VERSION_CACHE")" == "$CACHE_ROOT/make-version-cache" ]] || exit 125
[[ "$(realpath -m "$CARGO_HOME_CACHE")" == "$CACHE_ROOT/make-cargo-home" ]] || exit 125
[[ "$(realpath -m "$RUSTUP_HOME_CACHE")" == "$CACHE_ROOT/make-rustup-home" ]] || exit 125
[[ "$(realpath -m "$GO_MOD_CACHE")" == "$CACHE_ROOT/make-go-mod-cache" ]] || exit 125
[[ "$(realpath -m "$GO_SUMDB_CACHE")" == "$CACHE_ROOT/make-go-sumdb-cache" ]] || exit 125
[[ "$(realpath -m "$DEBOOTSTRAP_CACHE")" == "$CACHE_ROOT/make-debootstrap-cache" ]] || exit 125
[[ "$(realpath -m "$ROOTFS_APT_CACHE")" == "$CACHE_ROOT/make-rootfs-apt-cache" ]] || exit 125
[[ -f "$GIT_CONFIG" && "$(grep -c 'insteadOf =' "$GIT_CONFIG")" -eq 17 ]] || exit 125
[[ "$(find "$GIT_MIRROR_ROOT" -type d -name objects | wc -l)" -eq 17 ]] || exit 125
mkdir -p "$STAGE_ROOT" "$VERSION_CACHE" "$CARGO_HOME_CACHE" "$RUSTUP_HOME_CACHE" "$GO_MOD_CACHE" "$GO_SUMDB_CACHE" "$DEBOOTSTRAP_CACHE" "$ROOTFS_APT_CACHE"
chmod 0777 "$VERSION_CACHE" "$CARGO_HOME_CACHE" "$RUSTUP_HOME_CACHE" "$GO_MOD_CACHE" "$GO_SUMDB_CACHE" "$DEBOOTSTRAP_CACHE" "$ROOTFS_APT_CACHE"
exec 9>"$RUN_DIR/make-measurement.lock"
flock -n 9 || exit 124
prepare_dependency_caches
seed_debootstrap_cache
seed_watchdog_rust_dependencies

finish() {
    local status=$?
    printf '%s\n' "$status" > "$STAGE_ROOT/runner-status.tmp"
    mv "$STAGE_ROOT/runner-status.tmp" "$STAGE_ROOT/runner-status.txt"
    date -Iseconds > "$STAGE_ROOT/end-time.txt"
}
trap finish EXIT

cd "$REPO"
date -Iseconds > "$STAGE_ROOT/start-time.txt"
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" record-environment "$STAGE"
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE-clean" \
    env "${SEED_ENV[@]}" BLDENV=trixie make -f Makefile.work "${COMMON[@]}" clean
prepare_dependency_caches
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE-init" \
    env "${SEED_ENV[@]}" make "${COMMON[@]}" init
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE-configure" \
    env "${SEED_ENV[@]}" make "${COMMON[@]}" configure
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" run-timed "$STAGE-build" \
    env "${SEED_ENV[@]}" make "${COMMON[@]}" GOPROXY=https://goproxy.cn,direct target/sonic-vs.bin
[[ -f target/sonic-vs.bin ]]
[[ -s "$DEBOOTSTRAP_TARBALL" ]]
grep -qx 'arch=amd64' "$DEBOOTSTRAP_TARBALL.metadata"
grep -qx 'distro=trixie' "$DEBOOTSTRAP_TARBALL.metadata"
[[ -s "$ROOTFS_APT_CACHE/cache.tgz" ]]
[[ -s "$ROOTFS_APT_CACHE/docker.asc" ]]
[[ -n "$(find "$VERSION_CACHE" -type f -print -quit)" ]]
[[ -n "$(find "$CARGO_HOME_CACHE" -type f -print -quit)" ]]
[[ -x "$RUSTUP_HOME_CACHE/bin/rustc" ]]
[[ -n "$(find "$RUSTUP_HOME_CACHE/registry" -type f -print -quit)" ]]
[[ -n "$(find "$GO_MOD_CACHE" -type f -print -quit)" ]]
[[ -n "$(find "$GO_SUMDB_CACHE" -type f -print -quit)" ]]
seed_multistage_watchdog_apt_caches
rm -rf "$FIPS_CACHE"
mkdir -p "$FIPS_CACHE"
find target/debs/trixie -maxdepth 1 -type f \
    \( -name '*+fips*.deb' -o -name 'symcrypt-openssl_*.deb' \) \
    -exec cp -a {} "$FIPS_CACHE/" \;
[[ "$(find "$FIPS_CACHE" -type f -name '*.deb' | wc -l)" -eq 27 ]]
find "$FIPS_CACHE" -type f -name '*.deb' -size 0 -print -quit | grep -q . && exit 125 || true
{
    du -sh "$VERSION_CACHE" "$FIPS_CACHE" "$CARGO_HOME_CACHE" "$GO_MOD_CACHE" "$GO_SUMDB_CACHE"
    find "$VERSION_CACHE" -type f | wc -l
    find "$FIPS_CACHE" -type f -name '*.deb' | wc -l
    find "$CARGO_HOME_CACHE" -type f | wc -l
    find "$GO_MOD_CACHE" -type f | wc -l
    find "$GO_SUMDB_CACHE" -type f | wc -l
} > "$STAGE_ROOT/cache-summary.txt"
RUN_DIR="$RUN_DIR" CACHE_ROOT="$CACHE_ROOT" "$MEASURE" verify-artifact "$STAGE" \
    "$REPO/target/sonic-vs.bin"

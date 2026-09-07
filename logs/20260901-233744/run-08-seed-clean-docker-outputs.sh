#!/usr/bin/env bash
set -Eeuo pipefail

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE=08-seed-clean-docker-outputs
STAGE_ROOT="$RUN_DIR/$STAGE"
RUSTUP_HOME_CACHE="$CACHE_ROOT/make-rustup-home"
COMMON=(PLATFORM=vs NOJESSIE=1 NOSTRETCH=1 NOBUSTER=1 NOBULLSEYE=1 NOBOOKWORM=1 NOTRIXIE=0 ENABLE_DOCKER_BASE_PULL=n SONIC_CONFIG_USE_CCACHE=n SONIC_DPKG_CACHE_METHOD=none SONIC_VERSION_CACHE_METHOD=none BUILD_SKIP_TEST=y SONIC_BUILD_JOBS=8 SONIC_CONFIG_MAKE_JOBS=192 TRUSTED_GPG_URLS=)
TARGETS=(
    target/docker-base-trixie.gz
    target/docker-bmp-watchdog.gz
    target/docker-config-engine-trixie.gz
    target/docker-dash-engine.gz
    target/docker-dash-ha.gz
    target/docker-database.gz
    target/docker-dhcp-relay.gz
    target/docker-eventd.gz
    target/docker-fpm-frr.gz
    target/docker-gbsyncd-vs.gz
    target/docker-gnmi-sidecar.gz
    target/docker-gnmi-watchdog.gz
    target/docker-lldp.gz
    target/docker-macsec.gz
    target/docker-mux.gz
    target/docker-nat.gz
    target/docker-orchagent.gz
    target/docker-platform-monitor.gz
    target/docker-restapi-sidecar.gz
    target/docker-router-advertiser.gz
    target/docker-sflow.gz
    target/docker-snmp.gz
    target/docker-sonic-bmp.gz
    target/docker-sonic-gnmi.gz
    target/docker-sonic-mgmt-framework.gz
    target/docker-sonic-otel.gz
    target/docker-swss-layer-trixie.gz
    target/docker-syncd-vs.gz
    target/docker-sysmgr.gz
    target/docker-teamd.gz
)

[[ "$(realpath -m "$REPO")" == "$REPO" ]] || exit 125
[[ "$(realpath -m "$STAGE_ROOT")" == "$RUN_DIR/$STAGE" ]] || exit 125
[[ "$REPO" != /data/sonic/sonic-dzf ]] || exit 125
[[ -x "$RUSTUP_HOME_CACHE/bin/rustc" ]] || exit 125

mkdir -p "$STAGE_ROOT"
exec 9>"$RUN_DIR/make-measurement.lock"
flock -n 9 || exit 124
rm -rf "$STAGE_ROOT"
mkdir -p "$STAGE_ROOT"
finish() {
    local status=$?
    printf '%s\n' "$status" > "$STAGE_ROOT/runner-status.txt"
}
trap finish EXIT

cd "$REPO"
stat -c '%n %s bytes %y' "${TARGETS[@]}" > "$STAGE_ROOT/polluted-docker-outputs.txt"
rm -f "${TARGETS[@]}"
for target in "${TARGETS[@]}"; do
    rm -f "$target.log"
done

if /usr/bin/time -v -o "$STAGE_ROOT/time.txt" \
    env "SONIC_BUILDER_EXTRA_CMDLINE=-v $RUSTUP_HOME_CACHE:/rustup-home:ro" \
    make "${COMMON[@]}" "${TARGETS[@]}" > "$STAGE_ROOT/build.log" 2>&1; then
    for target in "${TARGETS[@]}"; do
        [[ -s "$target" ]] || exit 125
    done
    stat -c '%n %s bytes %y' "${TARGETS[@]}" > "$STAGE_ROOT/clean-docker-outputs.txt"
    sha256sum "${TARGETS[@]}" > "$STAGE_ROOT/clean-docker-outputs.sha256"
else
    exit $?
fi

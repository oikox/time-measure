#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=/data/sonic/sonic-dzf-time-measure
PRE="$ROOT/src/sonic-build-hooks/scripts/pre_run_buildinfo"
POST="$ROOT/src/sonic-build-hooks/scripts/post_run_buildinfo"
COLLECT="$ROOT/scripts/collect_docker_version_files.sh"
SEED="/data/sonic/时间统计/logs/20260901-233744/run-08-seed-make-dependencies.sh"

python3 - "$PRE" "$POST" "$COLLECT" "$SEED" <<'PY'
from pathlib import Path
import sys

pre = Path(sys.argv[1]).read_text()
post = Path(sys.argv[2]).read_text()
collect = Path(sys.argv[3]).read_text()
seed = Path(sys.argv[4]).read_text()

assert '${PKG_CACHE_PATH}/apt-lists' in pre
assert "find ${PKG_CACHE_PATH}/deb -maxdepth 1 -type f -name '*.deb' -exec cp -f {} /var/cache/apt/archives/ \\;" in pre
assert 'restored_deb_count=' in pre
assert 'cp -a ${PKG_CACHE_PATH}/apt-lists/. /var/lib/apt/lists/' in pre
assert 'rsync -avzh --ignore-errors /var/lib/apt/lists/ ${PKG_CACHE_PATH}/apt-lists/' in pre
assert 'DPkg::Pre-Install-Pkgs' in pre
assert 'cp -f {} ${PKG_CACHE_PATH}/deb/' in pre
assert 'rm -f /etc/apt/apt.conf.d/apt-clean' in pre
assert 'cp -a /var/lib/apt/lists/. ${PKG_CACHE_PATH}/apt-lists/' in pre
assert 'if [ "$(get_version_cache_option)" != rcache ]; then' in pre
assert '${PKG_CACHE_PATH}/apt-lists' in post
assert 'find /var/lib/apt/lists -maxdepth 1 -type f -print -quit' in post
assert 'cp -a /var/lib/apt/lists/. ${PKG_CACHE_PATH}/apt-lists/' in post
cache_guard = 'if [ ! -z "$(get_version_cache_option)" ]; then'
assert post.count(cache_guard) == 1, "cache export must have one explicit version-cache guard"
guard_start = post.index(cache_guard)
guard_end = post.index('\nfi', guard_start)
apt_collect = post.index('find /var/lib/apt/lists')
cache_tar = post.index('tar -C ${PKG_CACHE_PATH} --exclude=cache.tgz -zcvf /cache.tgz .')
assert guard_start < apt_collect < guard_end, "APT metadata collection must be version-cache-only"
assert guard_start < cache_tar < guard_end, "cache.tgz creation must be version-cache-only"
prepare = Path('/data/sonic/sonic-dzf-time-measure/scripts/prepare_docker_buildinfo.sh').read_text()
assert 'ENABLE_VERSION_CONTROL_DOCKER=n' in prepare
assert 'SONIC_VERSION_CONTROL_COMPONENTS//,/' in prepare
assert 'cp -a /pip-wheelhouse/. ${DOCKER_PATH}/vcache/pip-wheelhouse/' in prepare
assert 'ENV PIP_FIND_LINKS=/sonic/target/vcache/' in prepare
pip_cleanup = 'rm -rf ${DOCKER_PATH}/vcache/pip-wheelhouse\nif [ -d /pip-wheelhouse ]; then'
assert pip_cleanup in prepare, "stale pip wheelhouse must be removed even when no retained mount is present"
rust_cleanup = 'rm -rf ${DOCKER_PATH}/vcache/rustup-home\nif [[ "$IMAGENAME" == docker-bmp-watchdog || "$IMAGENAME" == docker-gnmi-watchdog ]]; then'
assert rust_cleanup in prepare, "stale Rust toolchain must be removed before optional watchdog staging"
assert '[[ ! -z ${SONIC_VERSION_CACHE} && -e ${LOCAL_CACHE_FILE} ]]' in collect
assert '[[ "$SONIC_VERSION_CACHE" != rcache || ! -e "$GLOBAL_CACHE_FILE" ]]' in collect
assert '[[ ! -z ${SONIC_VERSION_CACHE} && -e ${CACHE_ENCODE_FILE} ]]' not in collect
for token in (
    'seed_multistage_watchdog_apt_caches',
    'docker-config-engine-trixie',
    'docker-bmp-watchdog',
    'docker-gnmi-watchdog',
    '-size +1048576c',
):
    assert token in seed, f"dependency seed: missing multi-stage cache policy {token}"
assert 'cp -a /rustup-home/. ${DOCKER_PATH}/vcache/rustup-home/' in prepare
for dockerfile in (
    Path('/data/sonic/sonic-dzf-time-measure/dockers/docker-bmp-watchdog/Dockerfile.j2'),
    Path('/data/sonic/sonic-dzf-time-measure/dockers/docker-gnmi-watchdog/Dockerfile.j2'),
):
    text = dockerfile.read_text()
    assert 'COPY vcache/rustup-home/ $RUST_ROOT/' in text, f"{dockerfile.name}: missing retained Rust toolchain"
    assert 'curl --proto "=https" -sSf https://sh.rustup.rs' not in text, f"{dockerfile.name}: still downloads rustup"
    assert 'cargo build --release --offline --locked' in text, f"{dockerfile.name}: Cargo build is not offline"
print('build-hook offline apt cache policy: PASS')
PY

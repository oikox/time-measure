#!/usr/bin/env bash
set -Eeuo pipefail

python3 - <<'PY'
from pathlib import Path

root = Path("/data/sonic/时间统计/logs/20260901-233744")
cold_path = root / "run-07-make-fully-cold.sh"
offline_path = root / "run-08-make-deps-retained-offline.sh"
seed_path = root / "run-08-seed-make-dependencies.sh"
git_seed_path = root / "run-08-seed-git-mirrors.sh"

for path in (cold_path, offline_path, seed_path, git_seed_path):
    assert path.is_file(), f"missing runner: {path}"

cold = cold_path.read_text()
offline = offline_path.read_text()
seed = seed_path.read_text()
git_seed = git_seed_path.read_text()

common_tokens = (
    "set -Eeuo pipefail",
    "SONIC_BUILD_JOBS=8",
    "SONIC_CONFIG_MAKE_JOBS=192",
    "BUILD_SKIP_TEST=y",
    "NOBOOKWORM=1",
    "NOTRIXIE=0",
    "ENABLE_DOCKER_BASE_PULL=n",
    "SONIC_CONFIG_USE_CCACHE=n",
    "SONIC_DPKG_CACHE_METHOD=none",
    "realpath -m \"$REPO\"",
    "flock -n 9",
    "/usr/bin/time -v",
    "verify-artifact",
)
for path, text in ((cold_path, cold), (offline_path, offline)):
    for token in common_tokens:
        assert token in text, f"{path.name}: missing {token}"
    init = text.index('"$STAGE-init"')
    configure = text.index('"$STAGE-configure"')
    build = text.index('"$STAGE-build"')
    assert init < configure < build, f"{path.name}: stages are not ordered"
    if path == offline_path:
        run_build = text[text.index("run_build() {"):text.index("run_stages() {")]
        restore = run_build.index("    restore_fips_cache")
        refresh = run_build.index("    refresh_retained_outputs")
        make = run_build.index('    env "${OFFLINE_ENV[@]}" BLDENV=trixie make')
        assert restore < refresh < make, "offline runner must restore timed inputs and refresh retained files before Make"
        assert '"$SCRIPT" --run-build' in text[build:], "offline stage timer must invoke the build wrapper"

assert "SONIC_VERSION_CACHE_METHOD=none" in cold, "fully cold runner must disable version cache"

for token in (
    "git clean -fdX",
    "git submodule foreach --recursive",
    "docker image rm -f",
    "docker builder prune -af",
    "root-clean-preview.txt",
    "submodule-clean-preview.txt",
    "[[ ! -e target ]]",
    "[[ ! -e dpkg ]]",
):
    assert token in cold, f"cold runner: missing {token}"
assert "git clean -ndX -- . ':(exclude).measure' ':(exclude).alinos'" in cold, "cold preview must pathspec-exclude protected state"
assert "git clean -fdX -- . ':(exclude).measure' ':(exclude).alinos'" in cold, "cold cleanup must pathspec-exclude protected state"
assert 'docker run --rm --network none --userns=host --user 0:0 --entrypoint /bin/bash -v "$REPO:/repo" "${TAGS[0]}"' in cold, "cold runner must use host UID 0 when cleaning root-owned trees"
assert "rm -rf -- /repo/fsroot-vs /repo/fsroot.docker.* /repo/dpkg /repo/target" in cold, "cleanup helper must remove only guarded build trees"
assert "sudo -n" not in cold, "cold runner must not require interactive sudo"

for token in (
    "target/vcache",
    "vcache_inventory",
    "clear_compiled_outputs",
    "compiled-outputs-before-clean.txt",
    "compiled-outputs-after-clean.txt",
    "refresh_retained_outputs",
    "retained-output.timestamp",
    "touch -c -r \"$timestamp\"",
    "find target -type f",
    "! -path 'target/vcache/*'",
    "! -path 'target/debs/*'",
    "! -path 'target/python-wheels/*'",
    "! -name 'docker-*.gz'",
    "! -path 'target/sonic-vs.bin'",
    "! -path 'target/sonic-vs.bin__vs__rfs.squashfs'",
    "-exec touch -c -r \"$timestamp\" {} +",
    "vcache-before-clean.sha256",
    "vcache-after-clean.sha256",
    "cmp -s",
    "rm -rf -- /repo/fsroot-vs /repo/target/debs /repo/target/python-wheels",
    "find target -maxdepth 1 -type f -name 'docker-*.gz' -delete",
    "rm -f target/sonic-vs.bin__vs__rfs.squashfs target/sonic-vs.bin",
    "make-version-cache",
    "make-fips-cache",
    "make-git-mirrors",
    "offline.gitconfig",
    "SONIC_BUILDER_EXTRA_CMDLINE=",
    ":/git-mirrors:ro",
    ":/etc/sonic-offline.gitconfig:ro",
    "GIT_CONFIG_GLOBAL=/etc/sonic-offline.gitconfig",
    "find \"$FIPS_CACHE\" -type f -name '*.deb'",
    "cp -f \"$FIPS_CACHE\"/*.deb \"$REPO/target/debs/trixie/\"",
    "SONIC_VERSION_CACHE_METHOD=rcache",
    "SONIC_VERSION_CACHE_SOURCE=$VERSION_CACHE",
    "find \"$VERSION_CACHE\" -type f -print -quit",
    "sonic-build-hooks_1.0_all.deb",
    "retained-sonic-build-hooks",
    "07-make-fully-cold/slave-images.txt",
    "TRUSTED_GPG_URLS=",
    "cp -a",
    "user-image-retained.json",
    "base-image-retained.json",
    "http_proxy=http://127.0.0.1:9",
    "https_proxy=http://127.0.0.1:9",
    "HTTP_PROXY=http://127.0.0.1:9",
    "HTTPS_PROXY=http://127.0.0.1:9",
    "ALL_PROXY=http://127.0.0.1:9",
    "GOPROXY=off",
    "CARGO_NET_OFFLINE=true",
    "npm_config_offline=true",
    "PIP_NO_INDEX=1",
    "GIT_TERMINAL_PROMPT=0",
    "[[ ! -e target/sonic-vs.bin ]]",
):
    assert token in offline, f"offline runner: missing {token}"

assert "BLDENV=trixie make -f Makefile.work" in seed, "dependency seed clean must select trixie explicitly"
assert "SONIC_VERSION_CACHE_METHOD=cache" in seed, "dependency seed must populate the dedicated version cache"
assert "SONIC_VERSION_CACHE_SOURCE=$VERSION_CACHE" in seed, "dependency seed must use the formal cache source"
assert "make-fips-cache" in seed, "dependency seed must retain prebuilt FIPS packages"
assert "find target/debs/trixie -maxdepth 1 -type f" in seed, "dependency seed must collect FIPS packages"
for text, name in ((seed, "seed"), (offline, "offline")):
    for token in (
        "make-cargo-home",
        ":/cargo-home:rw",
        "-e CARGO_HOME=/cargo-home",
        "-e DEB_BUILD_OPTIONS=nocheck",
        "make-rustup-home",
        ":/rustup-home:",
    ):
        assert token in text, f"{name} runner: missing Cargo cache policy {token}"
assert ":/rustup-home:rw" in seed, "dependency seed must populate the fixed Rust toolchain"
assert ":/rustup-home:ro" in offline, "formal runner must mount the fixed Rust toolchain read-only"
assert "seed_watchdog_rust_dependencies" in seed, "dependency seed must fetch both watchdog Cargo.lock closures"
assert "-e CARGO_NET_OFFLINE=true" not in seed, "dependency seed must allow Cargo to populate its cache"
assert "-e CARGO_NET_OFFLINE=true" in offline, "formal runner must force Cargo offline inside the slave"
assert 'find "$CARGO_HOME_CACHE" -type f -print -quit' in offline, "formal runner must reject an empty Cargo cache"
for text, name in ((seed, "seed"), (offline, "offline")):
    for token in (
        "make-go-mod-cache",
        ":/tmp/go/pkg/mod:rw",
        "-e GOMODCACHE=/tmp/go/pkg/mod",
        "make-go-sumdb-cache",
        ":/tmp/go/pkg/sumdb:rw",
    ):
        assert token in text, f"{name} runner: missing Go dependency cache policy {token}"
assert 'find "$GO_MOD_CACHE" -type f -print -quit' in offline, "formal runner must reject an empty Go module cache"
assert 'find "$GO_SUMDB_CACHE" -type f -print -quit' in offline, "formal runner must reject an empty Go checksum database cache"
for token in (
    "make-pip-wheelhouse",
    ":/pip-wheelhouse:ro",
    "-e PIP_NO_INDEX=1",
    "-e PIP_FIND_LINKS=/pip-wheelhouse",
    "restore_fips_cache",
):
    assert token in offline, f"formal runner: missing offline package input policy {token}"
restore_calls = [line for line in offline.splitlines() if line.strip() == "restore_fips_cache"]
assert restore_calls == ["    restore_fips_cache"], "FIPS inputs must be restored exactly once inside the timed build wrapper"
assert '"$SCRIPT" --run-build' in offline, "formal build timing must include FIPS input restoration"
for text, name in ((seed, "seed"), (offline, "offline")):
    for token in (
        "make-debootstrap-cache",
        "make-rootfs-apt-cache",
        "SONIC_DEBOOTSTRAP_TARBALL",
        "SONIC_ROOTFS_APT_CACHE",
        "SONIC_ROOTFS_DOCKER_GPG_KEY",
    ):
        assert token in text, f"{name} runner: missing rootfs dependency input policy {token}"
assert ":/rootfs-cache:rw" in seed, "dependency seed must populate rootfs dependency inputs"
assert ":/rootfs-cache:ro" in offline, "formal runner must mount rootfs dependency inputs read-only"
assert 'find "$ROOTFS_APT_CACHE/extra-debs" -type f -name' in offline, "formal runner must validate supplemental early APT inputs"
for token in (
    '[[ ! -e "$REPO/fsroot-vs" ]]',
    '[[ ! -e target/debs ]]',
    '[[ ! -e target/python-wheels ]]',
    '[[ -z "$(find target -maxdepth 1 -type f -name \'docker-*.gz\' -print -quit)" ]]',
    '[[ ! -e target/sonic-vs.bin__vs__rfs.squashfs ]]',
    '[[ ! -e target/sonic-vs.bin ]]',
):
    assert token in offline, f"formal runner: missing product-cold assertion {token}"
for token in (
    "make-git-mirrors",
    "offline.gitconfig",
    ":/git-mirrors:ro",
    ":/etc/sonic-offline.gitconfig:ro",
    "GIT_CONFIG_GLOBAL=/etc/sonic-offline.gitconfig",
):
    assert token in seed, f"dependency seed must reuse fixed Git mirrors: missing {token}"
for token in (
    "git clone --mirror",
    "remote update --prune",
    "protocol \"file\"",
    "allow = always",
    "name = SONiC Build",
    "email = build@localhost",
    "insteadOf =",
    "required-ref",
):
    assert token in git_seed, f"Git mirror seed: missing {token}"
assert git_seed.count("mirror ") >= 17, "Git mirror seed must cover every reachable repository"
for text, name in ((seed, "seed"), (offline, "offline")):
    assert "--network none --userns=host --user 0:0" in text, f"{name} runner must prepare cache without network"
    assert "chmod -R a+rwx /cache" in text, f"{name} runner must make cache writable to the slave user"

assert '"SONIC_BUILDER_EXTRA_CMDLINE=$BUILDER_EXTRA"' in offline, "offline runner must preserve builder mounts as one environment element"
assert "SONIC_VERSION_CACHE_SOURCE=$VERSION_CACHE SONIC_BUILDER_EXTRA_CMDLINE" not in offline, "builder arguments must not enter recursive MAKEFLAGS"
assert 'env "${OFFLINE_ENV[@]}" BLDENV=trixie make -f Makefile.work MAKEFLAGS= "${COMMON[@]}" target/sonic-vs.bin' in offline, "formal build must call Makefile.work directly with explicit variables and no forced rebuild flag"
assert offline.count('MAKEFLAGS=') == 1, "only the formal build may suppress forced rebuilds"
assert 'make -f Makefile.work "${COMMON[@]}" clean' not in offline, "offline runner must not delete retained dependency outputs through generic clean"
assert "git clean -fdX" not in offline, "offline runner must retain downloaded dependencies"
assert "showtag" not in offline, "offline runner must not invoke a phony Make target to resolve retained image tags"
assert "docker image rm -f" not in offline, "offline runner must retain slave images"
assert "docker builder prune" not in offline, "offline runner must retain builder cache"
print("make measurement runner policy: PASS")
PY

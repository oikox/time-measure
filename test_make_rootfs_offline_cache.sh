#!/usr/bin/env bash
set -Eeuo pipefail

python3 - <<'PY'
from pathlib import Path

repo = Path("/data/sonic/sonic-dzf-time-measure")
base = (repo / "scripts/build_debian_base_system.sh").read_text()
build = (repo / "build_debian.sh").read_text()
collect = (repo / "scripts/collect_host_image_version_files.sh").read_text()
extension = (repo / "files/build_templates/sonic_debian_extension.j2").read_text()

for token in (
    "SONIC_DEBOOTSTRAP_TARBALL",
    "${SONIC_DEBOOTSTRAP_TARBALL}.metadata",
    'arch=$CONFIGURED_ARCH',
    'distro=$IMAGE_DISTRO',
    '--unpack-tarball=$SONIC_DEBOOTSTRAP_TARBALL',
):
    assert token in base, f"base-system script: missing retained debootstrap behavior {token}"

for token in (
    "SONIC_ROOTFS_OFFLINE",
    "SONIC_ROOTFS_APT_CACHE",
    "SONIC_ROOTFS_DOCKER_GPG_KEY",
    "cache.tgz",
    "extra-debs",
    "SONIC_ROOTFS_PIP_WHEELHOUSE",
    "PIP_NO_INDEX=1 PIP_FIND_LINKS=/pip-wheelhouse",
    "Skipping apt-clean in offline mode",
    "Skipping Debian apt-get update in offline mode",
    "Using retained Docker archive key",
    "Skipping Docker apt-get update in offline mode",
):
    assert token in build, f"rootfs build: missing offline input behavior {token}"

assert build.count('if [[ "${SONIC_ROOTFS_OFFLINE:-n}" != y ]]') >= 2, "both host and Docker apt updates must be gated"
assert "SONIC_ROOTFS_APT_CACHE" in collect, "host-image collection must publish the retained APT cache"
assert "SONIC_VERSION_CACHE" in collect and "rcache" in collect, "read-only formal mode must not republish cache inputs"
assert "cp -f $FILESYSTEM_ROOT/cache.tgz" in collect, "host cache archive must be copied from the rebuilt rootfs"
assert "install_external_pip_package()" in extension, "final installer must centralize external pip installs"
assert 'PIP_NO_INDEX=1 PIP_FIND_LINKS=/pip-wheelhouse' in extension, "final installer pip must use retained wheelhouse offline"
assert 'chroot $FILESYSTEM_ROOT pip3 install "redis==3.5.3"' not in extension, "final installer must not bypass offline pip helper"
print("make rootfs offline cache policy: PASS")
PY

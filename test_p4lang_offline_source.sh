#!/usr/bin/env bash
set -Eeuo pipefail

REPO=/data/sonic/sonic-dzf-time-measure
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/out"
cp "$REPO/src/p4lang/Makefile" "$TMP/Makefile"
for dsc in p4lang-pi_0.1.1-1.dsc p4lang-bmv2_1.15.0-9.dsc p4lang-p4c_1.2.4.2-2.dsc; do
  printf 'test source metadata\n' > "$TMP/$dsc"
done
printf 'immutable-p4c-source\n' > "$TMP/p4lang-p4c_1.2.4.2.orig.tar.gz"

cat > "$TMP/bin/dget" <<'EOF'
#!/usr/bin/env bash
exit 97
EOF
cat > "$TMP/bin/dpkg-source" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$2" >> "$DPKG_SOURCE_LOG"
case "$2" in
  *p4lang-pi_*) mkdir -p p4lang-pi-0.1.1 ;;
  *p4lang-bmv2_*) mkdir -p p4lang-bmv2-1.15.0 ;;
  *p4lang-p4c_*) mkdir -p p4lang-p4c-1.2.4.2 ;;
esac
EOF
cat > "$TMP/bin/patch" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TMP/bin/dpkg-buildpackage" <<'EOF'
#!/usr/bin/env bash
set -eu
[[ "${DEB_BUILD_OPTIONS:-}" == *nocheck* ]] || {
  printf 'missing DEB_BUILD_OPTIONS=nocheck\n' >&2
  exit 99
}
case " $* " in
  *' -Pnocheck '*) ;;
  *) printf 'missing -Pnocheck: %s\n' "$*" >&2; exit 98 ;;
esac
case "$(basename "$PWD")" in
  p4lang-pi-*) touch ../p4lang-pi_0.1.1-1_amd64.deb ;;
  p4lang-bmv2-*) touch ../p4lang-bmv2_1.15.0-9_amd64.deb ;;
  p4lang-p4c-*)
    printf 'mutated-by-debian-clean\n' > ../p4lang-p4c_1.2.4.2.orig.tar.gz
    touch ../p4lang-p4c_1.2.4.2-2_amd64.deb
    ;;
esac
EOF
chmod +x "$TMP/bin/"*

export PATH="$TMP/bin:$PATH"
export DPKG_SOURCE_LOG="$TMP/dpkg-source.log"
make -C "$TMP" -f Makefile \
  DEST="$TMP/out" CONFIGURED_ARCH=amd64 SONIC_CONFIG_MAKE_JOBS=1 BUILD_SKIP_TEST=y \
  SONIC_DPKG_ADMINDIR="$TMP/dpkg" CROSS_BUILD_ENVIRON=n \
  P4LANG_PI_VERSION=0.1.1 P4LANG_PI_VERSION_FULL=0.1.1-1 \
  P4LANG_BMV2_VERSION=1.15.0 P4LANG_BMV2_VERSION_FULL=1.15.0-9 \
  P4LANG_P4C_VERSION=1.2.4.2 P4LANG_P4C_VERSION_FULL=1.2.4.2-2 \
  "$TMP/out/p4lang-pi_0.1.1-1_amd64.deb" \
  "$TMP/out/p4lang-bmv2_1.15.0-9_amd64.deb" \
  "$TMP/out/p4lang-p4c_1.2.4.2-2_amd64.deb" >/dev/null

diff -u <(printf '%s\n' \
  './p4lang-pi_0.1.1-1.dsc' \
  './p4lang-bmv2_1.15.0-9.dsc' \
  './p4lang-p4c_1.2.4.2-2.dsc') "$DPKG_SOURCE_LOG"
grep -Fx 'immutable-p4c-source' "$TMP/p4lang-p4c_1.2.4.2.orig.tar.gz" >/dev/null

for package in pi bmv2 p4c; do
  grep -F "if [[ -f p4lang-${package}_\$(P4LANG_" "$REPO/src/p4lang/Makefile" >/dev/null
  grep -F "http://download.opensuse.org/repositories/home:/p4lang/Debian_11/p4lang-${package}_\$(P4LANG_" "$REPO/src/p4lang/Makefile" >/dev/null
done
[[ $(grep -c 'dpkg-source -x ./p4lang-' "$REPO/src/p4lang/Makefile") -eq 3 ]]
[[ $(grep -c 'dget -u http://download.opensuse.org/repositories/home:/p4lang/Debian_11/p4lang-' "$REPO/src/p4lang/Makefile") -eq 3 ]]

grep -F 'NOBOOKWORM=1 NOTRIXIE=0 BLDENV=trixie BUILD_SKIP_TEST=y TRUSTED_GPG_URLS=' "$REPO/src/p4lang/BUILD.bazel" >/dev/null
grep -F 'DOCKER_ROOT=$$P4_DOCKER_ROOT' "$REPO/src/p4lang/BUILD.bazel" >/dev/null
grep -F 'ifeq (,$(filter nocheck,$(DEB_BUILD_OPTIONS)))' \
  "$REPO/src/p4lang/p4lang-pi.patch/serialize-grpc-tests.patch" >/dev/null
grep -F 'ifeq (,$(filter nocheck,$(DEB_BUILD_OPTIONS)))' \
  "$REPO/src/p4lang/p4lang-bmv2.patch/serialize-grpc-tests.patch" >/dev/null

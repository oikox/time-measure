#!/usr/bin/env bash
set -Eeuo pipefail

REPO=/data/sonic/sonic-dzf-time-measure
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/out"
cp "$REPO/src/lldpd/Makefile" "$TMP/Makefile"
printf 'test source metadata\n' > "$TMP/lldpd_1.0.16-1+deb12u1.dsc"

cat > "$TMP/bin/dget" <<'EOF'
#!/usr/bin/env bash
exit 97
EOF
cat > "$TMP/bin/dpkg-source" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$2" > "$DPKG_SOURCE_LOG"
mkdir -p lldpd-1.0.16
EOF
cat > "$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TMP/bin/stg" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$TMP/bin/dpkg-buildpackage" <<'EOF'
#!/usr/bin/env bash
set -eu
touch ../lldpd_1.0.16-1+deb12u1_amd64.deb
touch ../liblldpctl-dev_1.0.16-1+deb12u1_amd64.deb
touch ../lldpd-dbgsym_1.0.16-1+deb12u1_amd64.deb
EOF
chmod +x "$TMP/bin/"*

export PATH="$TMP/bin:$PATH"
export DPKG_SOURCE_LOG="$TMP/dpkg-source.log"
make -C "$TMP" -f Makefile \
  DEST="$TMP/out" \
  LLDPD=lldpd_1.0.16-1+deb12u1_amd64.deb \
  LIBLLDPCTL=liblldpctl-dev_1.0.16-1+deb12u1_amd64.deb \
  LLDPD_DBG=lldpd-dbgsym_1.0.16-1+deb12u1_amd64.deb \
  LLDPD_VERSION=1.0.16 LLDPD_VERSION_FULL=1.0.16-1+deb12u1 \
  BUILD_PUBLIC_URL=https://packages.trafficmanager.net/public \
  CROSS_BUILD_ENVIRON=n CONFIGURED_ARCH=amd64 \
  SONIC_CONFIG_MAKE_JOBS=1 SONIC_DPKG_ADMINDIR="$TMP/dpkg" \
  "$TMP/out/lldpd_1.0.16-1+deb12u1_amd64.deb" >/dev/null

grep -Fx './lldpd_1.0.16-1+deb12u1.dsc' "$DPKG_SOURCE_LOG" >/dev/null
grep -F 'if [[ -f $(DSC_FILE) ]]; then' "$REPO/src/lldpd/Makefile" >/dev/null
grep -F 'dpkg-source -x ./$(DSC_FILE)' "$REPO/src/lldpd/Makefile" >/dev/null
grep -F 'dget $(DSC_FILE_URL)' "$REPO/src/lldpd/Makefile" >/dev/null

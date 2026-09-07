#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE=/data/sonic/sonic-dzf-time-measure/src/sonic-nettools/Makefile
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/src/sonic-nettools" "$TMP/rules" "$TMP/bin" "$TMP/out"
cp "$SOURCE" "$TMP/src/sonic-nettools/Makefile"
printf 'SONIC_NETTOOLS := sonic-nettools.deb\n' > "$TMP/rules/sonic-nettools.mk"
cat > "$TMP/bin/cargo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$CARGO_CALLS"
if [[ "$1" == build ]]; then
    mkdir -p target/release
    : > target/release/wol
fi
EOF
chmod +x "$TMP/bin/cargo"

CARGO_CALLS="$TMP/cargo.calls" PATH="$TMP/bin:$PATH" \
    make -C "$TMP/src/sonic-nettools" DEST="$TMP/out" DEB_BUILD_OPTIONS=nocheck \
    "$TMP/out/sonic-nettools.deb"

grep -Fxq 'build --release' "$TMP/cargo.calls"
if grep -q '^test' "$TMP/cargo.calls"; then
    printf 'cargo test ran despite DEB_BUILD_OPTIONS=nocheck\n' >&2
    exit 1
fi
printf 'sonic-nettools nocheck behavior: PASS\n'

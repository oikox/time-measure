#!/usr/bin/env bash
set -Eeuo pipefail

REPO=/data/sonic/sonic-dzf-time-measure
RUN_DIR=/data/sonic/时间统计/logs/20260901-233744
CACHE_ROOT=/data/sonic/时间统计/cache/20260901-233744
STAGE_ROOT="$RUN_DIR/08-make-deps-retained-offline-git-seed"
MIRROR_ROOT="$CACHE_ROOT/make-git-mirrors"
GIT_CONFIG="$CACHE_ROOT/offline.gitconfig"

[[ "$(realpath -m "$MIRROR_ROOT")" == "$CACHE_ROOT/make-git-mirrors" ]] || exit 125
mkdir -p "$STAGE_ROOT" "$MIRROR_ROOT"
exec 9>"$RUN_DIR/make-measurement.lock"
flock -n 9 || exit 124
: > "$STAGE_ROOT/mirrors.txt"

mirror() {
    local url=$1 relative=$2 required=$3 source=$4
    local target="$MIRROR_ROOT/$relative"
    mkdir -p "$(dirname "$target")"
    if [[ -d "$target" ]]; then
        git -C "$target" remote set-url origin "$url"
        git -C "$target" remote update --prune
    elif [[ -n "$source" && -d "$source" ]] && git -C "$source" rev-parse --verify "${required}^{commit}" >/dev/null 2>&1; then
        git clone --mirror "$source" "$target"
        git -C "$target" remote set-url origin "$url"
    else
        git clone --mirror "$url" "$target"
    fi
    local commit
    commit=$(git -C "$target" rev-parse --verify "${required}^{commit}")
    git -C "$target" update-ref refs/heads/required-ref "$commit"
    printf '%s\t%s\t%s\t%s\n' "$url" "$relative" "$required" "$commit" >> "$STAGE_ROOT/mirrors.txt"
}

mirror https://salsa.debian.org/grub-team/grub.git salsa.debian.org/grub-team/grub.git refs/tags/debian/2.06-13+deb13u1 "$REPO/src/grub2/grub2"
mirror https://salsa.debian.org/tai271828/rasdaemon.git salsa.debian.org/tai271828/rasdaemon.git 51a7f485f8b2e2ae43e613f19c5a387595174132 "$REPO/src/rasdaemon/rasdaemon"
mirror https://salsa.debian.org/debian/monit.git salsa.debian.org/debian/monit.git refs/tags/debian/1%5.34.3-1 "$REPO/src/monit/monit"
mirror https://github.com/FreeRADIUS/freeradius-server.git github.com/FreeRADIUS/freeradius-server.git 5f715dba4d2dbdb268bf60fcc656352274930941 "$REPO/src/radius/pam/freeradius/freeradius-server"
mirror https://github.com/FreeRADIUS/pam_radius.git github.com/FreeRADIUS/pam_radius.git 149c25df84cf5cd0e9addd9346699a9ca8fdddd2 "$REPO/src/radius/pam/pam_radius"
mirror https://github.com/jeroennijhof/pam_tacplus.git github.com/jeroennijhof/pam_tacplus.git refs/tags/v1.4.1 "$REPO/src/tacacs/pam/pam_tacplus"
mirror https://github.com/daveolson53/libnss-tacplus.git github.com/daveolson53/libnss-tacplus.git 19008ab68d9d504aa58eb34d5f564755a1613b8b "$REPO/src/tacacs/nss/libnss-tacplus"
mirror https://github.com/daveolson53/audisp-tacplus.git github.com/daveolson53/audisp-tacplus.git 559c9f22edd4f2dea0ecedffb3ad9502b12a75b6 "$REPO/src/tacacs/audisp/audisp-tacplus"
mirror https://github.com/sflow/host-sflow github.com/sflow/host-sflow b9b61bc037aed4d3d0fac6b0b4d88bc78b7b485d "$REPO/src/sflow/hsflowd/host-sflow"
mirror https://github.com/sflow/sflowtool github.com/sflow/sflowtool 6c2963b1c1b75b384ba6c9ce27e6272fdc11dc25 "$REPO/src/sflow/sflowtool/sflowtool"
mirror https://github.com/Mellanox/libpsample.git github.com/Mellanox/libpsample.git e48fad2402500a2aeb73961729aad06f793ff46e "$REPO/src/sflow/psample/libpsample"
mirror https://github.com/CESNET/libyang-python.git github.com/CESNET/libyang-python.git refs/tags/v3.1.0 "$REPO/src/libyang3-py3/libyang-python"
mirror https://github.com/FRRouting/frr.git github.com/FRRouting/frr.git refs/tags/frr-10.5.4 "$REPO/src/sonic-frr/frr"
mirror https://github.com/sonic-net/DASH.git github.com/sonic-net/DASH.git d5c003dd7774c2b43f275c0233acc73a0ea28d2f "$REPO/src/dash-sai/DASH"
mirror https://github.com/opencomputeproject/SAI.git github.com/opencomputeproject/SAI.git 8dd59e5eba472f0e53e8db00530e7c6e5ce2a335 "$REPO/src/dash-sai/DASH/dash-pipeline/SAI/SAI"
mirror https://github.com/opencomputeproject/SAI-Challenger.git github.com/opencomputeproject/SAI-Challenger.git 2c165e521161c736f83c9fe6c174e724dc6881a7 "$REPO/src/dash-sai/DASH/test/SAI-Challenger"
mirror https://github.com/openconfig/oc-pyang.git github.com/openconfig/oc-pyang.git 4607fd1987d4f586aba03b40f222015cb3ef8161 "$REPO/src/sonic-mgmt-common/build/oc-community-linter"

{
    printf '[protocol "file"]\n\tallow = always\n'
    printf '[user]\n\tname = SONiC Build\n\temail = build@localhost\n'
    while IFS=$'\t' read -r url relative required commit; do
        printf '[url "file:///git-mirrors/%s"]\n\tinsteadOf = %s\n' "$relative" "$url"
    done < "$STAGE_ROOT/mirrors.txt"
} > "$GIT_CONFIG.tmp"
mv "$GIT_CONFIG.tmp" "$GIT_CONFIG"
[[ "$(wc -l < "$STAGE_ROOT/mirrors.txt")" -eq 17 ]]
[[ "$(grep -c 'insteadOf =' "$GIT_CONFIG")" -eq 17 ]]
du -sh "$MIRROR_ROOT" > "$STAGE_ROOT/size.txt"
printf '0\n' > "$STAGE_ROOT/runner-status.txt"

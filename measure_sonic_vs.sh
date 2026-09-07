#!/usr/bin/env bash
set -Eeuo pipefail

MEASURE_ROOT=/data/sonic/时间统计
REPO_ROOT=/data/sonic/sonic-dzf-time-measure

validate_paths() {
    local run_dir cache_root
    run_dir=$(realpath -m "${RUN_DIR:?RUN_DIR is required}")
    cache_root=$(realpath -m "${CACHE_ROOT:?CACHE_ROOT is required}")

    if [[ "$run_dir" != "$MEASURE_ROOT/logs/"* || "$run_dir" == "$MEASURE_ROOT/logs" ]]; then
        printf 'unsafe RUN_DIR: %s\n' "$run_dir" >&2
        return 2
    fi
    if [[ "$cache_root" != "$MEASURE_ROOT/cache/"* || "$cache_root" == "$MEASURE_ROOT/cache" ]]; then
        printf 'unsafe CACHE_ROOT: %s\n' "$cache_root" >&2
        return 2
    fi
    if [[ "$run_dir" == "$REPO_ROOT" || "$cache_root" == "$REPO_ROOT" ]]; then
        printf 'measurement paths must not equal repository root\n' >&2
        return 2
    fi
}

run_timed() {
    validate_paths
    local stage=${1:?stage is required}
    shift
    [[ "$stage" =~ ^[a-zA-Z0-9._-]+$ ]] || {
        printf 'unsafe stage name: %s\n' "$stage" >&2
        return 2
    }
    (( $# > 0 )) || {
        printf 'timed command is required\n' >&2
        return 2
    }

    local stage_dir="$RUN_DIR/$stage"
    mkdir -p "$stage_dir"
    printf '%q ' "$@" > "$stage_dir/command.txt"
    printf '\n' >> "$stage_dir/command.txt"
    date -Iseconds > "$stage_dir/start-time.txt"

    set +e
    /usr/bin/time -v -o "$stage_dir/time.txt" "$@" > "$stage_dir/build.log" 2>&1
    local status=$?
    set -e

    date -Iseconds > "$stage_dir/end-time.txt"
    printf '%s\n' "$status" > "$stage_dir/exit-code.txt"
    return "$status"
}

verify_artifact() {
    validate_paths
    local stage=${1:?stage is required}
    local artifact=${2:?artifact path is required}
    [[ "$stage" =~ ^[a-zA-Z0-9._-]+$ ]] || {
        printf 'unsafe stage name: %s\n' "$stage" >&2
        return 2
    }
    [[ -f "$artifact" ]] || {
        printf 'artifact not found: %s\n' "$artifact" >&2
        return 1
    }

    local stage_dir="$RUN_DIR/$stage"
    mkdir -p "$stage_dir"
    {
        printf 'path: %s\n' "$(realpath "$artifact")"
        stat -c 'size_bytes: %s' "$artifact"
        file "$artifact"
        sha256sum "$artifact"
    } > "$stage_dir/artifact.txt"
}

record_blocker() {
    validate_paths
    local stage=${1:?stage is required}
    local message=${2:?message is required}
    local blocker_log
    blocker_log=$(realpath -m "${BLOCKER_LOG:-$MEASURE_ROOT/构建卡点记录.md}")
    [[ "$blocker_log" == "$MEASURE_ROOT/"* ]] || {
        printf 'unsafe BLOCKER_LOG: %s\n' "$blocker_log" >&2
        return 2
    }
    {
        printf '\n### %s - %s\n\n' "$(date -Iseconds)" "$stage"
        printf '%s\n' "$message"
    } >> "$blocker_log"
}

record_environment() {
    validate_paths
    local stage=${1:?stage is required}
    [[ "$stage" =~ ^[a-zA-Z0-9._-]+$ ]] || {
        printf 'unsafe stage name: %s\n' "$stage" >&2
        return 2
    }

    local stage_dir="$RUN_DIR/$stage"
    mkdir -p "$stage_dir"
    {
        printf 'recorded_at=%s\n' "$(date -Iseconds)"
        printf 'git_head=%s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD)"
        git -C "$REPO_ROOT" status --short --branch
        git -C "$REPO_ROOT" submodule status --recursive
        uname -a
        lscpu
        free -h
        df -h /data /home
        docker system df
        if [[ -e "$CACHE_ROOT" ]]; then
            du -sh "$CACHE_ROOT"
        fi
        printenv http_proxy https_proxy HTTP_PROXY HTTPS_PROXY GOPROXY 2>/dev/null || true
    } > "$stage_dir/environment.txt" 2>&1
}

case "${1:-}" in
    dry-run)
        printf '%s\n' \
            01-bazel-fully-cold \
            02-make-fully-cold \
            03-bazel-deps-retained \
            04-make-deps-retained
        ;;
    validate)
        validate_paths
        ;;
    run-timed)
        shift
        run_timed "$@"
        ;;
    verify-artifact)
        shift
        verify_artifact "$@"
        ;;
    record-blocker)
        shift
        record_blocker "$@"
        ;;
    record-environment)
        shift
        record_environment "$@"
        ;;
    *)
        printf 'Usage: %s {dry-run|validate|run-timed|verify-artifact|record-blocker|record-environment}\n' "$0" >&2
        exit 2
        ;;
esac

#!/bin/bash
# 7일 경과한 *.log를 압축하고 압축한 지 30일이 지난 파일을 삭제한다.
set -euo pipefail
umask 027
shopt -s nullglob

log_dir="${AGENT_LOG_DIR:-/var/log/agent-app}"
archive_dir="${AGENT_ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}"
# tmp에는 아직 완성되지 않은 압축본의 경로를 둔다.
tmp=''
trap '[[ -z "$tmp" ]] || rm -f -- "$tmp"' EXIT

check_directories() {
    local dir
    for dir in "$log_dir" "$archive_dir"; do
        if [[ ! -d "$dir" || ! -r "$dir" || ! -w "$dir" || ! -x "$dir" ]]; then
            echo "[WARNING] Cannot access directory: $dir" >&2
            exit 1
        fi
    done
}

log_is_open() {
    local log="$1" fd
    for fd in /proc/[0-9]*/fd/*; do
        if [[ "$fd" -ef "$log" ]]; then
            return 0
        fi
    done
    return 1
}

compress_log() {
    local log="$1" modified="$2" before archive
    # 압축 중 다른 작성자가 파일을 교체하거나 수정하면 원본을 보존한다.
    before=$(stat -c '%d:%i:%s:%y:%z' -- "$log")
    tmp=$(mktemp -- "$archive_dir/.archive.XXXXXXXX")
    gzip -c -- "$log" > "$tmp"
    if [[ "$before" != "$(stat -c '%d:%i:%s:%y:%z' -- "$log")" ]]; then
        echo "[WARNING] Log changed during compression: $log" >&2
        exit 1
    fi
    chmod 640 "$tmp"
    archive="$archive_dir/${log##*/}.$modified.$(stat -c %i -- "$log").gz"
    if [[ -e "$archive" ]]; then
        # 압축본 저장 직후 중단된 작업은 내용이 같은 경우에만 이어서 처리한다.
        gzip -cd -- "$archive" | cmp -s -- - "$log"
    else
        ln -- "$tmp" "$archive"
    fi
    rm -- "$tmp"
    tmp=''
    rm -- "$log"
    echo "Archived: $archive"
}

archive_old_logs() {
    local cutoff log modified
    cutoff=$(( $(date +%s) - 7 * 86400 ))
    for log in "$log_dir"/*.log; do
        [[ -f "$log" && ! -L "$log" ]] || continue
        modified=$(stat -c %Y -- "$log")
        (( modified <= cutoff )) || continue
        if log_is_open "$log"; then
            echo "[WARNING] Log is open: $log" >&2
            continue
        fi
        compress_log "$log" "$modified"
    done
}

main() {
    check_directories
    archive_old_logs
    find "$archive_dir" -maxdepth 1 -type f -name '*.gz' ! -newermt '30 days ago' -delete
}

main

#!/bin/bash
# 사용법: report.sh [시작 시각 [종료 시각]] (양 끝 포함)
set -eu
export LC_ALL=C

log_file="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"
start=${1:-}
end=${2:-}
check_range() {
    local bound
    for bound in "$start" "$end"; do
        [[ -z "$bound" ]] && continue
        if [[ "$(date -d "$bound" '+%F %T' 2>/dev/null)" != "$bound" ]]; then
            echo "Invalid timestamp: $bound" >&2
            exit 2
        fi
    done
    if [[ -n "$end" && "$start" > "$end" ]]; then
        echo "Start is later than end" >&2
        exit 2
    fi
}

print_statistics() {
    awk -v start="$start" -v end="$end" '
        BEGIN {
            name[1]="CPU"
            name[2]="MEM"
            name[3]="DISK_USED"
        }
        NF != 6 || $3 !~ /^PID:[0-9]+$/ || $4 !~ /^CPU:[0-9]+([.][0-9]+)?%$/ ||
            $5 !~ /^MEM:[0-9]+([.][0-9]+)?%$/ || $6 !~ /^DISK_USED:[0-9]+([.][0-9]+)?%$/ {
            printf "Invalid monitor.log record on line %d\n", NR > "/dev/stderr"
            failed=1
            exit 1
        }
        {
            stamp=substr($0, 2, 19)
            if ((start && stamp < start) || (end && stamp > end)) next
            for (i=1; i<=3; i++) {
                split($(i+3), parts, ":")
                value=parts[2]+0
                sum[i]+=value
                if (!count || value < min[i]) {
                    min[i]=value
                    min_at[i]=stamp
                }
                if (!count || value > max[i]) {
                    max[i]=value
                    max_at[i]=stamp
                }
            }
            count++
        }
        END {
            if (failed) exit 1
            print "====== STATISTICS REPORT ======"
            for (i=1; count && i<=3; i++) {
                printf "[%s]\nAverage: %.1f%%\nMaximum: %.1f%% at %s\nMinimum: %.1f%% at %s\n", \
                    name[i], sum[i]/count, max[i], max_at[i], min[i], min_at[i]
            }
            printf "Data Points: %d\n", count
        }
    ' "$log_file"
}

if (( $# > 2 )); then
    echo "Usage: report.sh [YYYY-MM-DD HH:MM:SS] [YYYY-MM-DD HH:MM:SS]" >&2
    exit 2
fi
check_range
print_statistics

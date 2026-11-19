#!/bin/bash
#
# monitor.sh - Agent 앱 상태 점검 및 시스템 자원 로깅
#
# 종료 코드
#   0: 정상 (방화벽 비활성, 임계값 초과는 경고만 출력)
#   1: 프로세스 또는 포트 비정상, 로그 기록 실패
#
# cron은 로그인 환경을 불러오지 않으므로 PATH와 기본값을 스크립트에 고정한다.

set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C

AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

# 리눅스의 프로세스 이름(comm)은 15자로 잘리므로 잘린 이름으로 정확히 비교한다.
# pgrep -f는 실행 명령 문자열에 앱 이름이 들어간 셸까지 잡을 수 있어 쓰지 않는다.
APP_PROCESS="${APP_PROCESS:-agent-app-linux}"

LOG_FILE="$AGENT_LOG_DIR/monitor.log"
LOCK_FILE="$AGENT_LOG_DIR/.monitor.lock"

CPU_LIMIT=20
MEM_LIMIT=10
DISK_LIMIT=80

MAX_LOG_SIZE=$((10 * 1024 * 1024)) # 파일당 최대 10MB
MAX_ROTATED=9                      # monitor.log + 백업 9개 = 총 10개

fail() {
    echo "[ERROR] $1"
    exit 1
}

warn() {
    echo "[WARNING] $1"
}

# 앱은 부모와 실제 작업 프로세스로 실행되므로 가장 최근 PID를 고른다.
# 종료 후 회수되지 않은 좀비 프로세스는 실행 중이 아니므로 제외한다.
find_app_pid() {
    local pid state
    for pid in $(pgrep -x "$APP_PROCESS" | sort -rn); do
        state="$(ps -o stat= -p "$pid" 2>/dev/null)"
        state="${state// /}"
        if [[ -n "$state" && "$state" != Z* ]]; then
            echo "$pid"
            return 0
        fi
    done
    return 1
}

# /proc/stat의 누적 CPU 시간을 "전체 유휴" 형태로 출력한다.
read_cpu_times() {
    local _label user nice system idle iowait irq softirq steal _rest
    read -r _label user nice system idle iowait irq softirq steal _rest </proc/stat
    echo "$((user + nice + system + idle + iowait + irq + softirq + steal)) $((idle + iowait))"
}

# 부팅 후 누적값이 아닌 현재 사용률을 얻기 위해 1초 간격 두 표본의 차이를 계산한다.
get_cpu_usage() {
    local total1 idle1 total2 idle2
    read -r total1 idle1 <<<"$(read_cpu_times)"
    sleep 1
    read -r total2 idle2 <<<"$(read_cpu_times)"
    awk -v total=$((total2 - total1)) -v idle=$((idle2 - idle1)) \
        'BEGIN { if (total <= 0) print "0.0"; else printf "%.1f", (total - idle) * 100 / total }'
}

# 캐시를 제외하고 실제 사용 가능한 메모리를 반영하도록 MemAvailable을 사용한다.
get_mem_usage() {
    awk '/^MemTotal:/ { total = $2 } /^MemAvailable:/ { available = $2 }
        END { if (total > 0) printf "%.1f", (total - available) * 100 / total; else print "0.0" }' /proc/meminfo
}

# -P는 긴 장치 이름에서도 한 줄 출력을 보장한다.
get_disk_usage() {
    df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }'
}

# 소수 비교는 Bash 산술로 할 수 없어 awk를 사용한다.
exceeds() {
    awk -v value="$1" -v limit="$2" 'BEGIN { exit !(value > limit) }'
}

# ufw status는 root 권한이 필요하므로 sudoers에 허용된 명령만 호출하고,
# 사용할 수 없으면 설정 파일의 활성화 값으로 판단한다.
firewall_active() {
    local status
    if command -v ufw >/dev/null 2>&1; then
        status="$(sudo -n /usr/sbin/ufw status 2>/dev/null)"
        if [[ -n "$status" ]]; then
            [[ "$status" == *"Status: active"* ]]
            return
        fi
        grep -qsE '^ENABLED=yes' /etc/ufw/ufw.conf
        return
    fi
    if command -v firewall-cmd >/dev/null 2>&1; then
        [[ "$(firewall-cmd --state 2>/dev/null)" == "running" ]]
        return
    fi
    return 1
}

# 다음 줄을 쓰면 10MB를 넘는 경우 백업 번호를 하나씩 밀고 가장 오래된 파일을 지운다.
rotate_log() {
    local next_line_size="$1" size i
    size="$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)"
    ((size + next_line_size <= MAX_LOG_SIZE)) && return 0

    rm -f "$LOG_FILE.$MAX_ROTATED"
    for ((i = MAX_ROTATED - 1; i >= 1; i--)); do
        [[ -f "$LOG_FILE.$i" ]] && mv -f "$LOG_FILE.$i" "$LOG_FILE.$((i + 1))"
    done
    mv -f "$LOG_FILE" "$LOG_FILE.1"
}

echo "====== SYSTEM MONITOR RESULT ======"
echo
echo "[HEALTH CHECK]"

APP_PID="$(find_app_pid)" || fail "Process '$APP_PROCESS' is not running"
echo "Checking process '$APP_PROCESS'... [OK] (PID: $APP_PID)"

[[ -n "$(ss -H -ltn "sport = :$AGENT_PORT")" ]] || fail "Port $AGENT_PORT is not listening"
echo "Checking port $AGENT_PORT... [OK]"

echo
echo "[FIREWALL]"
if firewall_active; then
    echo "Firewall status... [OK] (active)"
else
    warn "Firewall is not active"
fi

CPU_USAGE="$(get_cpu_usage)"
MEM_USAGE="$(get_mem_usage)"
DISK_USAGE="$(get_disk_usage)"

echo
echo "[RESOURCE MONITORING]"
echo "CPU Usage : ${CPU_USAGE}%"
echo "MEM Usage : ${MEM_USAGE}%"
echo "DISK Used : ${DISK_USAGE}%"
echo

exceeds "$CPU_USAGE" "$CPU_LIMIT" && warn "CPU threshold exceeded (${CPU_USAGE}% > ${CPU_LIMIT}%)"
exceeds "$MEM_USAGE" "$MEM_LIMIT" && warn "MEM threshold exceeded (${MEM_USAGE}% > ${MEM_LIMIT}%)"
exceeds "$DISK_USAGE" "$DISK_LIMIT" && warn "DISK threshold exceeded (${DISK_USAGE}% > ${DISK_LIMIT}%)"

LOG_LINE="[$(date '+%Y-%m-%d %H:%M:%S')] PID:${APP_PID} CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USAGE}%"

# 수동 실행과 cron이 겹쳐도 로그 교체와 기록이 섞이지 않도록 잠근다.
exec 9>>"$LOCK_FILE" || fail "Cannot open lock file: $LOCK_FILE"
flock -w 10 9 || fail "Cannot acquire log lock: $LOCK_FILE"

rotate_log "$((${#LOG_LINE} + 1))" || fail "Log rotation failed: $LOG_FILE"
echo "$LOG_LINE" >>"$LOG_FILE" || fail "Cannot write log: $LOG_FILE"

echo
echo "[INFO] Log appended: $LOG_FILE"
exit 0

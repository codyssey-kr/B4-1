#!/bin/bash
#
# verify-b4-1.sh - 평가 체크리스트의 구현 항목을 컨테이너에서 자동 점검한다.
#
# 사용법: ./scripts/verify-b4-1.sh
# 앱을 종료하지 않으며, 시험용 로그는 임시 디렉토리에 기록하고 삭제한다.

DOCKER_CONTEXT_NAME="${B4_DOCKER_CONTEXT:-orbstack}"
CONTAINER="${B4_CONTAINER:-b4-1}"

docker --context "$DOCKER_CONTEXT_NAME" exec -i "$CONTAINER" bash -s <<'EOF'
H=/home/agent-admin/agent-app
M=$H/bin/monitor.sh
L=/var/log/agent-app/monitor.log
PASS=0
FAIL=0

section() { printf '\n[%s]\n' "$1"; }

c() {
    if eval "$2" >/dev/null 2>&1; then
        PASS=$((PASS + 1)); echo "PASS  $1"
    else
        FAIL=$((FAIL + 1)); echo "FAIL  $1"
    fi
}

in_group() { id -nG "$1" | tr ' ' '\n' | grep -qx "$2"; }
can() { su - "$1" -c "$2"; }
mode_is() { [ "$(stat -c '%U:%G:%a' "$1")" = "$2" ]; }
env_is() { [ "$(su - agent-admin -c "printenv $1")" = "$2" ]; }

# 앱에 영향을 주지 않도록 쓰기 가능한 임시 로그 디렉토리에서 실행한다.
TMP_LOG=$(mktemp -d /tmp/verify-log.XXXXXX)
chown agent-admin "$TMP_LOG"
run_monitor() { su - agent-admin -c "AGENT_LOG_DIR=$TMP_LOG $1 $M"; }

rotation_works() {
    local t rc
    t=$(mktemp -d /tmp/verify-rot.XXXXXX)
    chown agent-admin "$t"
    su - agent-admin -c "
        cd $t
        for i in 1 2 3 4 5 6 7 8 9; do echo backup-\$i > monitor.log.\$i; done
        head -c 10485750 /dev/zero | tr '\0' x > monitor.log
        AGENT_LOG_DIR=$t $M >/dev/null
        [ \$(ls monitor.log monitor.log.[0-9] | wc -l) -eq 10 ] &&
        [ \$(stat -c %s monitor.log) -lt 1024 ] &&
        [ \$(stat -c %s monitor.log.1) -eq 10485750 ] &&
        [ \"\$(cat monitor.log.9)\" = backup-8 ]
    "
    rc=$?
    rm -rf "$t"
    return $rc
}

section "SSH"
c "sshd 포트가 20022이다" 'sshd -T | grep -qx "port 20022"'
c "Root 원격 로그인이 차단되어 있다" 'sshd -T | grep -qx "permitrootlogin no"'
c "20022 포트가 LISTEN 상태이다" '[ -n "$(ss -H -ltn "sport = :20022")" ]'
c "기존 22 포트는 LISTEN 상태가 아니다" '[ -z "$(ss -H -ltn "sport = :22")" ]'

section "방화벽"
c "UFW가 활성화되어 있다" 'ufw status | grep -qx "Status: active"'
c "기본 인바운드 정책이 deny이다" 'ufw status verbose | grep -q "deny (incoming)"'
c "허용 규칙이 20022/tcp, 15034/tcp뿐이다" '[ "$(ufw status | awk "/ALLOW/{print \$1}" | sort -u | tr "\n" " ")" = "15034/tcp 20022/tcp " ]'

section "계정과 그룹"
for u in agent-admin agent-dev agent-test; do
    c "$u 계정이 있다" "id $u"
    c "$u 는 agent-common 그룹이다" "in_group $u agent-common"
done
c "agent-admin은 agent-core 그룹이다" 'in_group agent-admin agent-core'
c "agent-dev는 agent-core 그룹이다" 'in_group agent-dev agent-core'
c "agent-test는 agent-core 그룹이 아니다" '! in_group agent-test agent-core'

section "디렉토리와 권한"
c "upload_files 그룹은 agent-common이다" "mode_is $H/upload_files agent-admin:agent-common:2770"
c "api_keys 그룹은 agent-core이다" "mode_is $H/api_keys agent-admin:agent-core:2770"
c "로그 디렉토리 그룹은 agent-core이다" 'mode_is /var/log/agent-app agent-admin:agent-core:2770'
for u in agent-admin agent-dev agent-test; do
    c "$u 는 upload_files에 쓸 수 있다" "can $u 'touch $H/upload_files/.v_$u && rm $H/upload_files/.v_$u'"
done
for u in agent-admin agent-dev; do
    c "$u 는 api_keys를 읽고 쓸 수 있다" "can $u 'cat $H/api_keys/t_secret.key && touch $H/api_keys/.v_$u && rm $H/api_keys/.v_$u'"
    c "$u 는 로그 디렉토리에 쓸 수 있다" "can $u 'touch /var/log/agent-app/.v_$u && rm /var/log/agent-app/.v_$u'"
done
c "agent-test는 api_keys를 읽을 수 없다" "! can agent-test 'cat $H/api_keys/t_secret.key'"
c "agent-test는 로그 디렉토리를 읽을 수 없다" "! can agent-test 'ls /var/log/agent-app'"
c "agent-test는 앱 출력 파일을 읽을 수 없다" "! can agent-test 'cat $H/app.out'"

section "앱 실행 환경"
c "AGENT_HOME 값이 맞다" "env_is AGENT_HOME $H"
c "AGENT_PORT 값이 맞다" 'env_is AGENT_PORT 15034'
c "AGENT_UPLOAD_DIR 값이 맞다" "env_is AGENT_UPLOAD_DIR $H/upload_files"
c "AGENT_KEY_PATH 값이 앱 요구와 맞다" "env_is AGENT_KEY_PATH $H/api_keys"
c "AGENT_LOG_DIR 값이 맞다" 'env_is AGENT_LOG_DIR /var/log/agent-app'
c "키 파일 내용이 1줄로 맞다" "[ \"\$(cat $H/api_keys/t_secret.key)\" = agent_api_key_test ] && [ \"\$(wc -l < $H/api_keys/t_secret.key)\" -eq 1 ]"
c "앱이 root가 아닌 일반 계정으로 실행 중이다" '[ -n "$(ps -o user= -C agent-app-linux)" ] && ! ps -o user= -C agent-app-linux | grep -qx root'
c "Boot Sequence 5단계가 모두 [OK]이다" "[ \"\$(grep -cE '^\[[1-5]/5\].*\[OK\]\$' $H/app.out)\" -eq 5 ]"
c "Agent READY가 출력되었다" "grep -qx 'Agent READY' $H/app.out"
c "앱이 0.0.0.0:15034에서 LISTEN 중이다" 'ss -H -ltn "sport = :15034" | grep -q "0.0.0.0:15034"'

section "monitor.sh"
c "위치, 소유자, 그룹, 권한이 맞다" "mode_is $M agent-dev:agent-core:750"
c "Bash 스크립트이다" "[ \"\$(head -n 1 $M)\" = '#!/bin/bash' ]"
c "agent-admin이 정상 실행하면 exit 0이다" 'run_monitor ""'
c "포트가 비정상이면 exit 1이다" '! run_monitor "AGENT_PORT=15999"; [ "$(run_monitor "AGENT_PORT=15999" >/dev/null 2>&1; echo $?)" = 1 ]'
c "프로세스가 비정상이면 exit 1이다" '[ "$(run_monitor "APP_PROCESS=no-such-proc" >/dev/null 2>&1; echo $?)" = 1 ]'
c "cron과 같은 빈 환경에서도 실행된다" "su agent-admin -s /bin/bash -c 'cd / && env -i AGENT_LOG_DIR=$TMP_LOG $M'"
c "자원 수치를 출력한다" 'run_monitor "" | grep -q "CPU Usage" && run_monitor "" | grep -q "MEM Usage" && run_monitor "" | grep -q "DISK Used"'

section "로그와 cron"
c "monitor.log가 있다" "[ -s $L ]"
c "모든 줄이 지정 포맷이다" "! grep -vE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] PID:[0-9]+ CPU:[0-9.]+% MEM:[0-9.]+% DISK_USED:[0-9]+%\$' $L"
c "agent-admin crontab에 매분 실행이 등록되어 있다" "crontab -u agent-admin -l | grep -qxF '* * * * * $M >/dev/null 2>&1'"
c "cron 서비스가 실행 중이다" 'service cron status'
c "최근 90초 안에 로그가 기록되었다" "[ \$(( \$(date +%s) - \$(date -d \"\$(tail -n 1 $L | cut -c2-20)\" +%s) )) -le 90 ]"
c "10MB 초과 시 교체하고 10개 파일을 유지한다" 'rotation_works'

rm -rf "$TMP_LOG"

printf '\n결과: PASS %d / FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
EOF

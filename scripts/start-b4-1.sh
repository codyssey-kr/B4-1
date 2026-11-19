#!/bin/bash
#
# start-b4-1.sh - Mac 재부팅이나 컨테이너 재시작 뒤 실습 환경을 평가 가능한 상태로 복구한다.
#
# 사용법: ./scripts/start-b4-1.sh

set -euo pipefail

DOCKER_CONTEXT_NAME="${B4_DOCKER_CONTEXT:-orbstack}"
CONTAINER="${B4_CONTAINER:-b4-1}"

docker --context "$DOCKER_CONTEXT_NAME" start "$CONTAINER" >/dev/null

docker --context "$DOCKER_CONTEXT_NAME" exec -i "$CONTAINER" bash -s <<'EOF'
set -euo pipefail

service ssh start >/dev/null
service cron start >/dev/null
ufw --force enable >/dev/null

if [[ -z "$(ss -H -ltn 'sport = :15034')" ]]; then
    su - agent-admin -c 'umask 027; cd "$AGENT_HOME" && AGENT_KEY_PATH="${AGENT_KEY_PATH%/t_secret.key}" nohup setsid ./agent-app-linux-arm64 > "$AGENT_HOME/app.out" 2>&1 < /dev/null &'
fi

for _ in $(seq 1 15); do
    [[ -n "$(ss -H -ltn 'sport = :15034')" ]] && break
    sleep 1
done

[[ -n "$(ss -H -ltn 'sport = :15034')" ]] || { echo "[ERROR] App did not start"; exit 1; }
echo "[OK] ssh, cron, ufw, and app are running"
EOF

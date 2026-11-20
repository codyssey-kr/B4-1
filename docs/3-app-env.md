# 3. 환경 변수와 앱 실행

목표: 환경 변수와 키 파일을 준비하고, 제공 앱을 일반 계정으로 실행해 Boot Sequence 5단계 `[OK]`와 `Agent READY`를 확인한다.

## 알아야 할 것

- **환경 변수**: 프로세스에 전달되는 `이름=값`. 프로그램은 코드를 고치지 않고 이 값으로 경로·포트를 정한다.
- `export NAME=value`는 현재 셸과 그 셸이 실행하는 프로그램에 값을 넘긴다.
- `/etc/profile.d/*.sh`는 모든 사용자의 **로그인 셸**이 시작할 때 읽는다. `su - 계정`은 로그인 셸이다.
- **cron은 이 파일을 읽지 않는다.** 그래서 cron으로 돌릴 스크립트는 필요한 값을 스크립트 안에 기본값으로 둔다(5단계 참고).
- **프로세스**: 실행 중인 프로그램. 번호(PID)로 구분한다.
- **root로 앱을 실행하지 않는 이유**: 앱에 취약점이 있으면 공격자는 앱을 실행한 계정의 권한을 얻는다. 일반 계정이면 피해가 그 계정의 권한으로 제한된다.

## 왜 환경 변수로 고정하는가

누가, 어떤 셸에서 실행하든 같은 경로와 포트를 쓰게 하기 위해서다. 제공 앱은 시작할 때 이 값이 맞는지 검사하고(Boot 2단계), 틀리면 실행을 멈춘다. 검증은 `su - agent-admin -c 'env | grep ^AGENT_'`로 로그인 셸의 실제 값을 보는 것이다.

## 수행 (root 셸)

```sh
cat > /etc/profile.d/agent-app.sh <<'EOF'
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key
export AGENT_LOG_DIR=/var/log/agent-app
EOF
. /etc/profile.d/agent-app.sh

printf 'agent_api_key_test\n' > "$AGENT_HOME/api_keys/t_secret.key"
chown agent-admin:agent-core "$AGENT_HOME/api_keys/t_secret.key"
chmod 660 "$AGENT_HOME/api_keys/t_secret.key"
ln -s t_secret.key "$AGENT_HOME/api_keys/secret.key"   # 앱이 찾는 파일 이름
```

제공 압축 파일의 실행 파일(이 실습은 arm64용 `agent-app-linux-arm64`)을 `$AGENT_HOME`에 두고 `agent-admin`으로 실행한다.

```sh
su - agent-admin -c 'cd "$AGENT_HOME" && AGENT_KEY_PATH="${AGENT_KEY_PATH%/t_secret.key}" nohup setsid ./agent-app-linux-arm64 > "$AGENT_HOME/app.out" 2>&1 < /dev/null &'
```

- `nohup setsid ... &`: 터미널을 닫아도 앱이 계속 돌게 백그라운드로 띄운다. 출력은 `app.out`에 남는다. 앞에서 직접 실행하고 `Ctrl+C`로 끝내도 과제 기준은 같다.
- `${AGENT_KEY_PATH%/t_secret.key}`: 값 끝의 `/t_secret.key`를 뗀다.

## 미션 문서와 다른 점

| 항목 | 문서 | 실제 | 이유 |
|---|---|---|---|
| `AGENT_KEY_PATH` | 키 파일 경로 | 로그인 셸은 문서대로, 앱 실행 명령에서만 디렉토리 경로 | 문서 값으로 실행하면 `Key Path Mismatch. Expected: .../api_keys`로 2단계 실패 |
| 키 파일 이름 | `t_secret.key` | `t_secret.key` + `secret.key` 심볼릭 링크 | 앱은 `secret.key`를 연다 |

## 확인

```sh
su - agent-admin -c 'env | grep ^AGENT_ | sort'
head -n 14 "$AGENT_HOME/app.out"      # [1/5]~[5/5] [OK], Agent READY
ss -ltnp 'sport = :15034'             # 0.0.0.0:15034 LISTEN
ps -o user=,pid=,args= -C agent-app-linux   # 실행 계정 agent-admin
```

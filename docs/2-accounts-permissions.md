# 2. 계정, 그룹, 디렉토리 권한

목표: 세 계정과 두 그룹을 만들고, 공유 디렉토리와 보안 디렉토리의 접근 범위를 나눈다.

| 계정 | 역할 | agent-common | agent-core |
|---|---|---|---|
| agent-admin | 운영, cron 실행 | O | O |
| agent-dev | 개발, monitor.sh 작성 | O | O |
| agent-test | QA | O | X |

| 경로 | 그룹 | 접근 가능 계정 |
|---|---|---|
| `$AGENT_HOME/upload_files` | agent-common | 세 계정 모두 R/W |
| `$AGENT_HOME/api_keys` | agent-core | admin, dev만 R/W |
| `/var/log/agent-app` | agent-core | admin, dev만 R/W |

## 알아야 할 것

- 파일마다 **소유자**, **그룹**, **기타** 세 대상에 대해 r(읽기), w(쓰기), x(실행) 권한이 있다.
- 숫자 표기: r=4, w=2, x=1. `750` = 소유자 rwx(7), 그룹 r-x(5), 기타 없음(0).
- 디렉토리에서 r은 목록 보기, w는 파일 생성·삭제, x는 안으로 들어가기(통과)다.
- **setgid 디렉토리**(`chmod 2770`의 앞자리 2): 안에서 새로 만든 파일이 디렉토리의 그룹을 물려받는다. 없으면 만든 사람의 기본 그룹이 붙어 다른 구성원이 못 읽는다.
- **ACL**: 기본 권한(소유자·그룹·기타 3칸) 외에 특정 그룹·사용자 권한을 추가로 지정한다. `setfacl -m`으로 설정, `getfacl`로 확인. `ls -l`에서 권한 뒤에 `+`가 붙는다.
- **기본 ACL**(`setfacl -d`): 디렉토리 안에 새로 생기는 파일에 자동으로 적용될 ACL이다.
- 그룹 소속 변경은 **새 로그인부터** 적용된다.

## 왜 나누는가 (최소 권한 원칙)

각 계정에 업무에 필요한 권한만 준다.

- `api_keys`의 키가 새면 외부 API를 남이 쓸 수 있다. QA는 키가 필요 없으므로 agent-core만 접근한다.
- 운영 로그에는 PID, 자원 사용량 같은 내부 정보가 있다. 운영과 개발만 필요하다.
- agent-test 계정이 탈취되어도 키와 운영 로그에는 접근할 수 없다.
- 권한을 사람이 아니라 그룹에 주므로, 담당자가 바뀌면 그룹 소속만 바꾸면 된다.

## 수행 (root 셸)

```sh
groupadd agent-common
groupadd agent-core
useradd -m -s /bin/bash agent-admin
useradd -m -s /bin/bash agent-dev
useradd -m -s /bin/bash agent-test
usermod -aG agent-common,agent-core agent-admin
usermod -aG agent-common,agent-core agent-dev
usermod -aG agent-common agent-test

AGENT_HOME=/home/agent-admin/agent-app
mkdir -p "$AGENT_HOME"/{upload_files,api_keys,bin} /var/log/agent-app

# 다른 계정이 $AGENT_HOME까지 들어갈 수 있도록 홈 디렉토리에 통과(x) 권한만 준다
chmod 750 /home/agent-admin
setfacl -m g:agent-common:--x /home/agent-admin
chown agent-admin:agent-common "$AGENT_HOME"
chmod 750 "$AGENT_HOME"

# 공유 디렉토리
chown agent-admin:agent-common "$AGENT_HOME/upload_files"
chmod 2770 "$AGENT_HOME/upload_files"
setfacl -m g:agent-common:rwx "$AGENT_HOME/upload_files"
setfacl -d -m g:agent-common:rwx "$AGENT_HOME/upload_files"

# 보안 디렉토리
for d in "$AGENT_HOME/api_keys" /var/log/agent-app; do
  chown agent-admin:agent-core "$d"
  chmod 2770 "$d"
  setfacl -m g:agent-core:rwx "$d"
  setfacl -d -m g:agent-core:rwx "$d"
done

# monitor.sh를 둘 디렉토리: agent-dev가 쓰고 agent-core가 실행한다
chown agent-dev:agent-core "$AGENT_HOME/bin"
chmod 2750 "$AGENT_HOME/bin"
```

## 확인

```sh
id agent-admin; id agent-dev; id agent-test
ls -ld "$AGENT_HOME"/{upload_files,api_keys,bin} /var/log/agent-app
getfacl -p "$AGENT_HOME/api_keys"
su - agent-test -c 'ls /var/log/agent-app'     # Permission denied 가 나와야 한다
su - agent-test -c 'touch ~agent-admin/agent-app/upload_files/t && echo ok'
```

# 4. monitor.sh: 상태 점검과 로그 한 줄

목표: 앱 프로세스와 포트를 확인하고(실패 시 `exit 1`), 방화벽과 자원 사용률을 점검해 경고를 출력한 뒤, `monitor.log`에 한 줄을 추가한다.

코드: [required/monitor.sh](../required/monitor.sh). 맨 아래 `main` 호출부터 읽는다.

## 실행 순서

```text
1. 프로세스 확인   없으면 [ERROR], exit 1
2. 포트 확인       LISTEN이 아니면 [ERROR], exit 1
3. 방화벽 확인     비활성이면 [WARNING], 계속
4. CPU·MEM·DISK 수집, 임계값 초과면 [WARNING], 계속
5. 10MB를 넘게 되면 로그 교체 (5단계 문서)
6. monitor.log에 한 줄 추가, exit 0
```

## 알아야 할 것

- 첫 줄 `#!/bin/bash`: 이 파일을 Bash로 실행하라는 표시.
- **종료 코드**: 모든 명령은 끝날 때 숫자를 돌려준다. 0은 성공, 나머지는 실패. 직전 값은 `$?`로 본다. `exit 1`은 스크립트를 실패로 끝낸다.
- `$(명령)`: 명령의 출력을 값으로 받는다. 예: `app_pid="$(find_app_pid)"`.
- `${AGENT_PORT:-15034}`: 변수가 비어 있으면 15034를 쓴다. cron처럼 환경 변수가 없는 실행에서도 동작하게 한다.
- Bash 산술은 정수만 다룬다. `25.3 > 20` 같은 소수 비교와 계산은 `awk`로 한다.
- `>`는 파일을 비우고 쓰고, `>>`는 파일 끝에 덧붙인다. 로그는 이전 기록을 남겨야 하므로 `>>`를 쓴다. `>`를 쓰면 매분 한 줄만 남는다.

## 프로세스와 포트 확인

| 확인 | 명령 | 선택 이유 |
|---|---|---|
| 프로세스 | `pgrep -x agent-app-linux` | `-x`는 프로세스 이름이 정확히 같을 때만 찾는다. `pgrep -f`는 명령줄 전체를 검색해 앱 이름이 들어간 다른 셸 명령까지 잡는다 |
| 좀비 제외 | `ps -o stat= -p PID` | 상태가 `Z`(좀비)면 이미 종료된 프로세스다. 목록에만 남아 있으므로 제외한다 |
| 포트 | `ss -H -ltn "sport = :15034"` | `-l` LISTEN만, `-t` TCP만, `-n` 숫자로, `-H` 머리글 없이. 출력이 비면 LISTEN이 아니다 |

리눅스의 프로세스 이름(comm)은 15바이트까지만 저장된다. 실행 파일 `agent-app-linux-arm64`는 `agent-app-linux`로 보이므로 그 이름으로 비교한다.

## 자원 사용률 계산

| 값 | 출처 | 계산 |
|---|---|---|
| CPU | `/proc/stat` 첫 줄 | 부팅 후 누적 시간이므로 1초 간격으로 두 번 읽어 차이를 쓴다. `(전체 증가 - 유휴 증가) / 전체 증가 × 100` |
| MEM | `/proc/meminfo` | `(MemTotal - MemAvailable) / MemTotal × 100`. MemAvailable은 캐시처럼 바로 회수할 수 있는 메모리를 포함한 실제 여유량이다 |
| DISK | `df -P /` | 두 번째 줄 5번째 칸(`Use%`)에서 `%`를 뺀다. `-P`는 장치 이름이 길어도 한 줄로 출력하게 한다 |

## 경고와 종료를 나눈 이유

| 상황 | 처리 | 이유 |
|---|---|---|
| 프로세스 없음, 포트 닫힘 | `exit 1` | 서비스가 요청을 받을 수 없는 장애다. 호출한 쪽이 실패로 알 수 있어야 한다 |
| 방화벽 비활성, 임계값 초과 | `[WARNING]` 후 계속 | 서비스는 동작 중이다. 특히 부하가 높을 때의 기록이 원인 분석에 필요하므로 로그를 남기고 끝난다 |

## 로그 포맷

```text
[2026-11-19 03:15:02] PID:969 CPU:0.1% MEM:5.5% DISK_USED:3%
```

모든 줄이 같은 형식이면 `grep`, `awk`로 시간 구간을 자르고 평균·최대를 계산할 수 있다(보너스 `report.sh`). 시각을 맨 앞에 두면 줄 순서가 곧 시간 순서다.

## 파일 권한: 작성자와 실행자

```sh
install -o agent-dev -g agent-core -m 750 monitor.sh "$AGENT_HOME/bin/monitor.sh"
```

- 소유자 agent-dev: rwx → 수정 가능.
- 그룹 agent-core: r-x → agent-admin(agent-core 소속)이 읽고 실행 가능. Bash 스크립트는 셸이 파일을 읽어야 실행되므로 r도 필요하다.
- 기타: 없음 → agent-test는 실행 불가.

방화벽 상태 조회(`ufw status`)는 root만 가능하므로, 이 명령 하나만 비밀번호 없이 허용했다.

```sh
echo 'agent-admin,agent-dev ALL=(root) NOPASSWD: /usr/sbin/ufw status' > /etc/sudoers.d/agent-monitor
chmod 440 /etc/sudoers.d/agent-monitor
```

## 확인

```sh
su - agent-admin -c "$AGENT_HOME/bin/monitor.sh"; echo "exit: $?"   # exit: 0
tail -n 3 /var/log/agent-app/monitor.log
su - agent-admin -c "AGENT_PORT=15999 $AGENT_HOME/bin/monitor.sh"; echo "exit: $?"   # 열리지 않은 포트 → exit: 1
```

## 응용 질문

- **대상이 Nginx로 바뀌면**: 프로세스 이름(`nginx`), 포트(80/443), 로그 경로(`/var/log/nginx/`)를 바꾼다. 임계값은 그 서버의 평소 사용량을 보고 다시 정한다. 포트가 열려 있어도 응답이 오는지 보려면 `curl -fsS http://127.0.0.1/` 같은 HTTP 요청 확인을 추가한다.
- **프로세스는 있는데 포트가 안 열릴 때** 확인 순서:
  1. 앱 출력·로그(`app.out`)에서 시작 오류를 본다.
  2. 아직 시작 중인지 본다(몇 초 뒤 다시 `ss`).
  3. `ss -ltnp`로 다른 포트나 `127.0.0.1`에만 열렸는지 본다(설정·환경 변수 오류).
  4. 다른 프로그램이 이미 그 포트를 쓰는지 본다.
  5. 프로세스 상태가 `Z`(좀비)나 `D`(멈춤)인지 `ps`로 본다.
- **로그가 급증해 디스크가 찰 위험**:
  - 단기: `df -h`, `du -sh /var/log/*`로 큰 파일을 찾고, 오래된 로그를 압축·삭제한다. 프로세스가 열고 있는 파일은 `rm`해도 공간이 돌아오지 않으므로 `: > 파일`로 비운다.
  - 중기: 로그 교체·보존 기간을 설정하고, 로그를 많이 쓰는 원인(반복 오류, 과한 로그 레벨)을 고친다. 디스크 사용률 경고 임계값으로 미리 알린다.

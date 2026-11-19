# 구현 설명

실제 설정 명령과 출력은 [수행 내역서](../required/B4-1-수행내역서.md)에 있다. 이 문서는 **무엇을 왜 그렇게 구현했는지** 설명한다.

## 1. 전체 구조

```text
macOS
└─ OrbStack
   └─ 컨테이너 b4-1 (Ubuntu 22.04, arm64)
      ├─ sshd :20022                 Root 로그인 차단
      ├─ UFW                         20022/tcp, 15034/tcp만 허용
      ├─ agent-app-linux-arm64 :15034  agent-admin으로 실행
      └─ cron (agent-admin)
         ├─ 매분 bin/monitor.sh → /var/log/agent-app/monitor.log
         └─ 매일 00:15 bin/archive-logs.sh → /var/log/monitor/agent-app/archive/
```

컨테이너의 20022, 15034 포트는 Mac의 `127.0.0.1`에만 연결했다.

## 2. 요구사항별 구현

| 요구사항 | 구현 | 이유 |
|---|---|---|
| SSH 포트 변경 | `Port 20022` | 22번을 노리는 자동화 공격 감소 |
| Root 차단 | `PermitRootLogin no` | 관리자 계정 직접 공격 차단, 작업자 추적 |
| 방화벽 | UFW 기본 차단, 2개 포트만 허용 | 허용 목록 방식으로 노출 최소화 |
| 공유 디렉토리 | `upload_files`: agent-common, 2770, ACL | 세 계정의 협업 공간 |
| 보안 디렉토리 | `api_keys`, 로그: agent-core, 2770, ACL | 키와 운영 로그를 QA 계정에서 분리 |
| 환경 변수 | `/etc/profile.d/agent-app.sh` | 로그인 셸의 실행 환경 고정 |
| 앱 실행 | `agent-admin` 백그라운드 실행 | root 실행 금지, 터미널 종료 후에도 유지 |
| 스크립트 권한 | `agent-dev:agent-core`, 750 | 파일 소유자는 수정 가능, 운영 계정은 읽기·실행 가능 |
| 자동 실행 | `agent-admin` crontab 매분 실행 | 운영 계정이 주기적으로 수집 |

### 권한 구조

| 경로 | 소유자:그룹 | 권한 | agent-admin | agent-dev | agent-test |
|---|---|---|---|---|---|
| `$AGENT_HOME` | agent-admin:agent-common | 750 | 전체 | 읽기, 통과 | 읽기, 통과 |
| `upload_files` | agent-admin:agent-common | 2770 + ACL | R/W | R/W | R/W |
| `api_keys` | agent-admin:agent-core | 2770 + ACL | R/W | R/W | 불가 |
| `bin/monitor.sh` | agent-dev:agent-core | 750 | 읽기, 실행 | 전체 | 불가 |
| `/var/log/agent-app` | agent-admin:agent-core | 2770 + ACL | R/W | R/W | 불가 |
| `app.out` | agent-admin:agent-core | 640 | R/W | 읽기 | 불가 |

`/home/agent-admin`은 750을 유지하고 ACL로 `agent-common`에 통과 권한(`--x`)만 줬다. 다른 계정은 홈의 파일 목록을 볼 수 없지만 `$AGENT_HOME`까지는 이동할 수 있다.

## 3. monitor.sh 동작

```text
시작
 ├─ 프로세스 확인 ─ 실패 → [ERROR], exit 1
 ├─ 포트 확인 ──── 실패 → [ERROR], exit 1
 ├─ 방화벽 확인 ── 비활성 → [WARNING], 계속
 ├─ CPU, MEM, DISK 수집
 ├─ 임계값 비교 ── 초과 → [WARNING], 계속
 ├─ 로그 잠금(flock)
 ├─ 10MB 초과 예정이면 로그 교체
 ├─ monitor.log에 한 줄 추가
 └─ exit 0
```

| 기능 | 사용 기술 | 선택 이유 |
|---|---|---|
| 프로세스 확인 | `pgrep -x`, `ps -o stat=` | 정확한 이름 일치, 좀비 제외 |
| 포트 확인 | `ss -H -ltn "sport = :PORT"` | LISTEN 소켓만 정확히 조회 |
| 방화벽 확인 | `sudo -n ufw status` | 현재 상태를 조회하고, 조회 출력이 없으면 UFW 설정의 `ENABLED=yes`를 확인 |
| CPU | `/proc/stat` 1초 간격 차이 | 1초 동안 전체 CPU 시간에서 유휴 시간의 비율을 제외 |
| 메모리 | `MemAvailable` | 회수 가능한 캐시를 사용량에서 제외 |
| 디스크 | `df -P /` | 안정적인 한 줄 출력 |
| 소수 비교 | `awk` | Bash 산술은 정수만 지원 |
| 동시 실행 보호 | `flock` | 수동 실행과 cron이 겹쳐도 안전 |

### 종료와 경고를 나눈 기준

| 상황 | 처리 | 이유 |
|---|---|---|
| 프로세스 없음, 포트 닫힘 | `exit 1` | 서비스 장애이므로 실패로 알린다. |
| 방화벽 비활성 | 경고 후 계속 | 서비스는 동작 중이며 조치가 필요한 위험 신호다. |
| CPU, MEM, DISK 임계값 초과 | 경고 후 계속 | 부하가 높을 때의 기록이 원인 분석에 가장 중요하다. |

### 로그 용량 관리

`monitor.log`에 새 줄을 쓰면 10MB를 넘는 경우에만 교체한다. 파일당 기준은 10 MiB(10,485,760바이트)다. 현재 파일 1개와 백업 최대 9개를 합쳐 로그 내용은 최대 100 MiB다.

## 4. 문제 해결 기록

| 문제 | 확인 방법 | 원인 | 해결 |
|---|---|---|---|
| Boot 2단계 실패 | 앱 메시지 `Key Path Mismatch` | 앱은 키 파일이 아니라 디렉토리 경로를 요구 | 로그인 환경에는 키 파일을 지정하고 앱 기동 명령에서만 파일명을 제거 |
| Boot 3단계 실패 | 앱 메시지 `Missing File: secret.key` | 앱이 찾는 파일명이 문서와 다름 | `secret.key` → `t_secret.key` 심볼릭 링크 |
| 프로세스 이름 불일치 | `ps -o comm` | 이 환경에서 comm이 15바이트로 잘림 | `agent-app-linux`로 정확히 비교 |
| `pgrep -f` 오탐 | 앱 실행 셸까지 검색됨 | 명령줄 전체를 검색 | `pgrep -x` 사용 |
| 종료된 앱을 실행 중으로 판단할 위험 | 컨테이너 PID 1 동작 검토 | 회수되지 않은 좀비도 `pgrep`에 잡힘 | `ps` 상태가 `Z`면 제외 |
| WSL 방화벽 간섭 | 배포판 간 네트워크 네임스페이스 비교 | WSL2 배포판이 네트워크를 공유 | 독립 네트워크를 쓰는 컨테이너로 변경 |
| `agent-test`가 앱 출력 읽기 가능 | 계정별 접근 시험 | `app.out` 기본 권한이 664 | `agent-core`, 640으로 변경 |
| 재시작 후 앱과 방화벽 중지 | 컨테이너 재시작 시험 | 컨테이너 시작 명령은 ssh, cron만 실행 | `scripts/start-b4-1.sh` 추가 |

## 5. 검증 방법

| 검증 | 방법 |
|---|---|
| Root 차단 | 임시 키를 등록해 일반 계정 성공, root 거부를 실제로 확인 |
| 방화벽 | 별도 컨테이너에서 20022, 15034 접속 성공, 임시 18080 차단 확인 |
| 권한 | 세 계정으로 읽기와 쓰기를 직접 시도 |
| 프로세스 장애 | 앱을 실제로 종료해 `exit 1` 확인 후 재시작 |
| 포트 장애 | 사용하지 않는 15999번을 점검 대상으로 지정해 `exit 1` 확인 |
| CPU 경고 | 전체 코어에 부하를 줘 실제 임계값으로 확인 |
| 메모리, 디스크 경고 | 입력 표본을 고정해 MEM 10%·DISK 80%에서 경고 없음, 10.1%·81%에서 경고 후 로그 누적 확인 |
| 로그 교체 | 10MB 직전 파일과 백업 9개로 교체 결과 확인 |
| cron | 수동 실행 없이 매분 로그가 증가하는지 확인 |
| 재시작 복구 | 컨테이너 재시작 후 복구 스크립트와 자동 점검 실행 |
| 점검 스크립트 | 방화벽을 일부러 꺼서 FAIL이 나오는지 확인 |

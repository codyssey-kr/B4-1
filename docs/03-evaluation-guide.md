# 평가 대비

미션 평가 체크리스트 19개 항목의 상태, 시연 방법, 답변을 정리했다.

## 평가 직전 준비

Mac이 잠들면 cron도 멈추므로 평가가 끝날 때까지 깨워 둔다. 프로젝트 루트에서 실행한다.

```sh
caffeinate -d &
./scripts/start-b4-1.sh
./scripts/verify-b4-1.sh
docker --context orbstack exec -it b4-1 bash
```

마지막 명령으로 컨테이너에 들어간 뒤 아래 시연 명령을 실행한다. 편의를 위해 경로를 변수로 지정한다.

```sh
M=/home/agent-admin/agent-app/bin/monitor.sh
L=/var/log/agent-app/monitor.log
```

## 항목 1. 구현 확인

| # | 체크 항목 | 상태 | 증거 |
|---|---|---|---|
| 1 | SSH 20022, Root 차단 | 완료 | 내역서 4.1 |
| 2 | 방화벽 활성화, 2개 포트만 허용 | 완료 | 내역서 4.2 |
| 3 | 계정과 그룹 구성 | 완료 | 내역서 4.3, 4.4 |
| 4 | Boot 5단계 [OK], Agent READY | 완료 | 내역서 4.5 |
| 5 | 비정상 상태에서 exit 1 | 완료 | 내역서 4.6 |
| 6 | monitor.log 지정 포맷 누적 | 완료 | 내역서 4.7 |
| 7 | cron 매분 자동 증가 | 완료 | 내역서 4.8 |
| 8 | 로그 용량 관리(10MB/10개) | 완료 | 내역서 4.9 |

체크리스트의 "Agent REDDY"는 미션 문서의 "Agent READY"를 잘못 적은 것으로 보고 READY를 기준으로 했다.

### 1. SSH

```sh
grep -nE '^(Port|PermitRootLogin)' /etc/ssh/sshd_config
sshd -T | grep -E '^(port|permitrootlogin) '
ss -tulnp | grep sshd
```

Mac 터미널에서 Root 접속이 거부되는지 확인한다.

```sh
ssh -p 20022 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@127.0.0.1
```

### 2. 방화벽

```sh
ufw status verbose
```

### 3. 계정과 그룹

```sh
id agent-admin; id agent-dev; id agent-test
getent group agent-common agent-core
ls -ld /home/agent-admin/agent-app/{upload_files,api_keys} /var/log/agent-app
getfacl -p /home/agent-admin/agent-app/api_keys
su - agent-test -c 'cat /home/agent-admin/agent-app/api_keys/t_secret.key'   # Permission denied
```

### 4. Boot Sequence

```sh
head -n 14 /home/agent-admin/agent-app/app.out
ss -ltn 'sport = :15034'
ps -o user,pid,args -C agent-app-linux
```

### 5. exit 1 동작

```sh
su - agent-admin -c "$M"; echo "exit: $?"                     # 정상: 0
su - agent-admin -c "AGENT_PORT=15999 $M"; echo "exit: $?"    # 포트 비정상: 1
pkill -INT -x agent-app-linux; sleep 3
su - agent-admin -c "$M"; echo "exit: $?"                     # 프로세스 비정상: 1
```

시연 후 Mac 터미널에서 `./scripts/start-b4-1.sh`로 앱을 다시 실행한다.

### 6~7. 로그와 cron

```sh
crontab -u agent-admin -l
tail -n 5 "$L"
wc -l "$L"; sleep 65; wc -l "$L"
```

### 8. 로그 용량 관리

`monitor.sh`의 `rotate_log` 함수를 보여주고, Mac 터미널에서 자동 점검의 마지막 항목을 확인한다.

```sh
./scripts/verify-b4-1.sh | grep '10MB'
```

### 경고 시연

평상시 CPU는 임계값보다 낮으므로 부하를 주어 보여준다.

```sh
for i in $(seq "$(nproc)"); do yes >/dev/null & done
su - agent-admin -c "$M"; echo "exit: $?"
pkill -x yes
```

## 항목 2. 구현 설명

### 9. 프로세스와 포트 확인 명령과 선택 이유

프로세스는 `pgrep -x agent-app-linux`로 이름이 정확히 일치하는 것만 찾는다. 리눅스 프로세스 이름은 15자로 잘려서 잘린 이름을 사용했다. `pgrep -f`는 명령줄 전체를 검색해 앱을 실행한 셸까지 찾을 수 있어 쓰지 않았고, `ps -o stat=`로 좀비 프로세스를 제외했다.

포트는 `ss -H -ltn "sport = :15034"`로 확인한다. `-l`은 LISTEN, `-t`는 TCP, `-n`은 숫자 표시이고 출력이 있으면 정상이다. `netstat`은 별도 패키지가 필요하고 `ss`는 Ubuntu에 기본 포함되어 있다.

### 10. CPU, MEM, DISK 추출과 로그 포맷

- **CPU**: `/proc/stat`은 누적값이므로 1초 간격으로 두 번 읽고, `(전체 증가량 - 유휴 증가량) / 전체 증가량`으로 계산한다.
- **MEM**: `/proc/meminfo`의 `(MemTotal - MemAvailable) / MemTotal`이다. 회수 가능한 캐시를 사용량에서 제외하기 위해 `MemAvailable`을 썼다.
- **DISK**: `df -P /`의 다섯 번째 열인 `Use%`다.
- **포맷 고정 이유**: 한 줄에 한 시점을 같은 순서로 기록하면 `grep`과 `awk`로 집계할 수 있고, 시간순 비교와 자동 분석이 쉽다.

### 11. 소유자와 실행자 권한 정책

`monitor.sh`는 `agent-dev:agent-core`, 750이다. 소유자 agent-dev만 수정할 수 있고, agent-core 그룹인 agent-admin은 읽기와 실행 권한으로 cron에서 실행한다. 스크립트는 해석기가 내용을 읽어야 하므로 그룹에 `r-x`가 필요하다. agent-test는 그룹에 속하지 않아 접근할 수 없다.

### 12. 용량 기반 로그 관리

스크립트 방식으로 구현했다. 새 줄을 기록하기 전에 크기를 확인해 10MB를 넘게 되면 `.8`→`.9`, ..., `monitor.log`→`.1` 순서로 이름을 바꾸고 가장 오래된 `.9`를 삭제한다. 현재 파일과 백업 9개로 총 10개다. logrotate는 보통 하루 주기로 실행되지만 스크립트는 매분 실행 시 바로 검사한다. 수동 실행과 cron이 겹치는 경우는 `flock`으로 보호했다.

## 항목 3. 보안과 운영

### 13. SSH 포트 변경과 Root 차단의 위협 모델

공격자는 인터넷 전체를 스캔해 22번 포트와 `root` 계정에 비밀번호를 대입한다. 포트 변경은 이런 자동화 공격의 시도를 줄이지만, 포트 스캔으로 찾을 수 있으므로 보조 수단이다. Root 차단은 공격자가 유효한 계정 이름을 알아내야 하게 만들고, 침입해도 권한 상승 단계를 추가로 거치게 한다. 또한 작업자가 개인 계정으로 접속하므로 감사 추적이 가능하다.

### 14. api_keys와 로그를 agent-core로 제한한 이유

최소 권한 원칙은 업무에 필요한 권한만 주는 것이다. QA 계정은 API 키와 운영 로그가 업무에 필요하지 않다. 제한해 두면 QA 계정이 탈취되어도 키 유출이나 로그 변조로 피해가 확산되지 않는다.

### 15. 경고와 종료를 분리한 운영상 이유

프로세스나 포트 실패는 서비스 장애이므로 `exit 1`로 자동화 도구에 실패를 알린다. 방화벽 비활성과 임계값 초과는 서비스가 동작 중인 위험 신호다. 이때 종료하면 **부하가 가장 높은 시점의 기록이 사라지므로** 경고만 남기고 수집을 계속한다.

### 16. `>`와 `>>`의 차이

`>`는 파일을 비우고 새로 쓰고, `>>`는 기존 내용 끝에 추가한다. 로그에 `>`를 쓰면 매분 이전 기록이 사라져 추이를 분석할 수 없으므로 `>>`가 필요하다.

## 항목 4. 장애 대응

### 17. 모니터링 대상이 Nginx로 바뀐다면

| 항목 | 변경 내용 |
|---|---|
| 프로세스 | `APP_PROCESS=nginx`, master 프로세스 확인 |
| 포트 | `AGENT_PORT`를 80 또는 443으로 변경 |
| 로그 | `/var/log/nginx/`의 access, error 로그와 교체 정책 확인 |
| 임계값 | 평상시 트래픽을 측정해 CPU, 메모리 기준 재설정 |
| 추가 점검 | `curl`로 HTTP 응답 코드 확인, 5xx 오류 비율 집계 |

프로세스와 포트가 정상이어도 웹 서버가 오류를 응답할 수 있으므로 HTTP 응답 확인을 추가한다.

### 18. 프로세스는 살아 있는데 포트가 열리지 않을 때

1. **앱 로그 확인**: 초기화 중인지, bind 오류(`Address already in use`)가 있는지 본다.
2. **포트 상태 확인**: `ss -ltnp`로 다른 포트나 `127.0.0.1`에 바인딩했는지, 다른 프로세스가 점유했는지 본다.
3. **설정 확인**: `AGENT_PORT` 등 환경 변수가 의도한 값인지 본다.
4. **프로세스 상태 확인**: `ps`로 `D`, `Z` 상태인지, 멈춰 있는지 본다.
5. **자원과 권한 확인**: 파일 권한, 파일 디스크립터 제한, 메모리 부족 기록을 본다.

방화벽은 외부 접근을 막을 뿐 LISTEN 상태를 없애지 않으므로 이 증상의 원인 후보가 아니다.

### 19. 로그 급증으로 디스크가 찰 위험이 있을 때

**단기 대응**

1. `df -h`, `du -sh /var/log/*`로 원인 파일을 찾는다.
2. 오래된 로그를 압축하거나 다른 저장소로 옮긴다.
3. 사용 중인 파일은 삭제 대신 `: > 파일`로 비운다. 삭제해도 프로세스가 파일을 열고 있으면 공간이 회수되지 않으며, `lsof +L1`로 확인할 수 있다.
4. 급증을 일으키는 오류나 디버그 로그를 멈춘다.

**중기 대응**

1. 급증의 근본 원인과 로그 레벨을 수정한다.
2. 용량과 기간 기반 보존 정책을 적용한다.
3. 디스크 사용률 알림을 설정한다.
4. 중앙 로그 시스템과 로그 전용 파티션을 도입한다.

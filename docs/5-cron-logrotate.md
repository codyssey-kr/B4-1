# 5. cron 매분 실행과 로그 용량 관리

목표: `agent-admin`의 crontab에 `monitor.sh`를 매분 등록하고, `monitor.log`를 최대 10MB × 10개로 유지한다.

## 알아야 할 것

- **cron**: 정해진 시각에 명령을 실행하는 서비스. 사용자마다 작업 목록(crontab)이 있고, 작업은 그 사용자 권한으로 실행된다.
- crontab 한 줄 = 시각 5칸 + 명령.

```text
분 시 일 월 요일  명령
*  *  *  *  *     매분
15 0  *  *  *     매일 00:15
```

- cron은 로그인 셸이 아니어서 `/etc/profile.d`의 환경 변수를 읽지 않고 `PATH`도 짧다. 그래서 `monitor.sh`는 `PATH`를 직접 지정하고 `AGENT_PORT`, `AGENT_LOG_DIR`에 기본값을 둔다.
- `>/dev/null 2>&1`: 화면 출력(표준 출력)과 오류 출력을 버린다. 기록은 스크립트가 `monitor.log`에 직접 남긴다.

## 수행

```sh
# root 셸에서 agent-admin의 crontab에 추가
( crontab -u agent-admin -l 2>/dev/null
  echo '* * * * * /home/agent-admin/agent-app/bin/monitor.sh >/dev/null 2>&1' ) | crontab -u agent-admin -
```

`agent-admin`으로 로그인했다면 `crontab -e`로 같은 줄을 추가해도 된다.

## 확인

```sh
crontab -u agent-admin -l
wc -l < /var/log/agent-app/monitor.log
# 1~2분 기다린 뒤
wc -l < /var/log/agent-app/monitor.log     # 줄 수가 늘었으면 성공
tail -n 3 /var/log/agent-app/monitor.log
```

## 로그 용량 관리 (10MB / 10개)

로그는 지우지 않으면 계속 커져 디스크를 채우고, 디스크가 차면 앱과 시스템이 파일을 쓰지 못해 장애가 난다. 그래서 크기 상한을 둔다.

`monitor.sh`의 `rotate_log` 함수가 매 기록 직전에 처리한다(logrotate 대신 스크립트 구현).

```text
현재 크기 + 새 줄 크기 > 10MB(10,485,760바이트) 이면:
  monitor.log.9 삭제
  monitor.log.8 → .9, ..., monitor.log.1 → .2
  monitor.log   → monitor.log.1
그 다음 새 monitor.log에 한 줄 기록
```

- 파일 수: 현재 `monitor.log` 1개 + 백업 `.1`~`.9` = 10개. 최대 약 100MB.
- 스크립트로 구현한 이유: 기록할 때마다 크기를 검사하므로 10MB를 넘지 않는다. logrotate는 보통 하루 한 번 실행되어 그 사이에 상한을 넘을 수 있다.
- logrotate로 할 경우 예: `/etc/logrotate.d/agent-app`에 `size 10M`, `rotate 9`를 쓰고 cron으로 자주 실행한다.

시험 방법: 10MB 직전 크기의 `monitor.log`와 백업 9개를 임시 디렉토리에 만들고 `AGENT_LOG_DIR=임시경로`로 실행한다. 결과는 [수행 내역서 4.9](../required/B4-1-수행내역서.md#49-로그-용량-관리10mb10개).

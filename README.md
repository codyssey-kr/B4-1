# B4-1 컴퓨터가 알아서 자기 상태를 점검하게 만들기

Ubuntu에서 SSH와 방화벽, 계정별 접근 권한을 구성하고, `agent-admin`의 cron으로 매분 앱 상태와 자원 사용률을 기록하는 과제다.

## 처음 배우는 순서

[첫 실습](docs/learn/01-shell.md)은 이미 구성된 Ubuntu에 들어가 로그 한 줄을 읽는 것부터 시작한다. 이어지는 명령은 같은 터미널에서 순서대로 실행할 수 있다.

| 순서 | 직접 해 보는 일 |
|---|---|
| [1. 셸과 로그](docs/learn/01-shell.md) | 긴 파일 경로에 이름을 붙이고, 처음 만든 함수로 최근 한 줄을 읽는다. |
| [2. 앱과 포트](docs/learn/02-health.md) | 앱을 찾고 포트를 확인한 다음, 찾을 수 없는 이름을 주어 종료 코드 1을 확인한다. |
| [3. 자원 사용률](docs/learn/03-resources.md) | 디스크 표에서 한 칸을 고르고 메모리·CPU 사용률이 나오는 과정을 따라간다. |
| [4. 기록과 자동 실행](docs/learn/04-log.md) | 연습 폴더에 실제 점검 결과 한 줄을 쓰고, 그 한 줄로 통계까지 낸다. |

## 과제 파일

| 구분 | 파일 | 확인할 내용 |
|---|---|---|
| 필수 제출물 | [수행 내역서](required/B4-1-수행내역서.md) · [monitor.sh](required/monitor.sh) | 설정 명령, 실행 증거, 상태 점검과 용량 기반 로그 교체 |
| 보너스 1 | [report.sh](bonus/report.sh) | 현재 로그 전체 또는 지정한 시간 구간의 자원 통계 |
| 보너스 2 | [archive-logs.sh](bonus/archive-logs.sh) | 7일 경과 로그 압축과 30일 경과 아카이브 삭제 |
| 보너스 검증 | [실행 예시와 결과](bonus/README.md) | 통계 계산, 압축 및 삭제 경계 시험 |

## 실습 환경에서 확인하기

Mac의 저장소 루트에서 아래 명령을 실행한다. `b4-1`은 [수행 내역서 3장](required/B4-1-수행내역서.md#3-수행-내역설정명령어-기록)에 따라 계정, 패키지, 프로필, 제공 앱까지 준비된 OrbStack 컨테이너다.

```sh
./scripts/start-b4-1.sh
./scripts/install-b4-1.sh
./scripts/verify-b4-1.sh
```

설치 스크립트는 `required/`와 `bonus/`의 세 스크립트를 컨테이너의 `/home/agent-admin/agent-app/bin/`에 설치한다. `agent-admin`의 crontab에는 매분 모니터링과 매일 00:15 로그 보존 작업을 등록한다. 검증은 실제 cron 기록을 최대 80초 기다린다.

## 설명 자료

- [배경지식](docs/01-background.md)에서 SSH, ACL, 자원 사용률 계산에 쓰인 리눅스 개념을 확인할 수 있다.
- [구현 설명](docs/02-implementation.md)은 계정별 권한, 프로세스와 포트 점검, 로그 교체 방식을 설명한다.
- [평가 대비](docs/03-evaluation-guide.md)는 체크리스트 19개 항목의 시연 명령과 설명을 담고 있다.
- [실습 환경과 구현 선택](docs/04-decisions.md)에 제공 앱의 키 경로와 컨테이너 운영 조건을 정리했다.

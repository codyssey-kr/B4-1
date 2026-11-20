# B4-1 컴퓨터가 알아서 자기 상태를 점검하게 만들기

Ubuntu 서버에 SSH·방화벽·계정 권한을 설정하고, 앱을 일반 계정으로 실행한 뒤, `monitor.sh`가 cron으로 매분 앱 상태와 자원 사용률을 로그에 남기게 하는 과제다.

## 제출물

- [수행 내역서](required/B4-1-수행내역서.md): 설정 명령과 실행 증거
- [monitor.sh](required/monitor.sh): 상태 점검, 자원 수집, 로그 기록, 10MB/10개 로그 교체

## 작은 과제로 나눈 순서

각 문서에 배경지식, 수행 명령, 확인 방법, 체크리스트 설명 질문의 답이 있다.

1. [SSH와 방화벽](docs/1-ssh-firewall.md)
2. [계정, 그룹, 디렉토리 권한](docs/2-accounts-permissions.md)
3. [환경 변수와 앱 실행](docs/3-app-env.md)
4. [monitor.sh: 상태 점검과 로그 한 줄](docs/4-monitor.md)
5. [cron 매분 실행과 로그 용량 관리](docs/5-cron-logrotate.md)

## 보너스 (선택)

- [report.sh](bonus/report.sh): 로그의 CPU/MEM/DISK 평균·최대·최소
- [archive-logs.sh](bonus/archive-logs.sh): 7일 경과 로그 압축, 30일 경과 아카이브 삭제
- 사용법과 시험 결과: [bonus/README.md](bonus/README.md)

## 실습 환경 스크립트

실습 환경은 OrbStack의 Ubuntu 22.04 컨테이너 `b4-1`이다. Mac의 저장소 루트에서 실행한다.

```sh
./scripts/start-b4-1.sh    # 재시작 후 ssh, cron, ufw, 앱 복구
./scripts/install-b4-1.sh  # 스크립트 설치, agent-admin crontab 등록
./scripts/verify-b4-1.sh   # 요구사항 자동 점검 (cron 확인에 최대 80초)
```

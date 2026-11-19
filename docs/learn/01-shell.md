# 첫 실습 · 터미널에서 로그 한 줄 읽기

앱은 요청을 기다리는 프로그램이다. 이 과제에서 만드는 `monitor.sh`는 그 앱이 살아 있는지 확인하고, 당시 컴퓨터 상태를 파일에 한 줄 남긴다. **cron**은 이 일을 매분 시작하는 예약 프로그램이다.

## 어디에서 입력할까?

Mac 터미널에서 아래 한 줄을 실행한다. 이 명령은 실행 중인 실습용 Ubuntu에 들어간다. 마지막의 `su - agent-admin`은 그 안에서 운영 계정으로 새 셸을 연다. 셸은 입력한 명령을 읽고 실행하는 프로그램이다. 이 과제의 `.sh` 파일은 첫 줄이 `#!/bin/bash`이므로 경로로 직접 실행하면 Bash가 명령을 읽는다.

컨테이너가 중지되어 있다는 메시지가 나오면 Mac에서 저장소 루트의 `./scripts/start-b4-1.sh`를 실행한 뒤 다시 들어간다.

```bash
docker --context orbstack exec -it b4-1 su - agent-admin
```

이제부터 명령은 **Ubuntu 안에서** 한 줄씩 입력한다. 아래 두 명령은 실행 중인 계정과 최근 기록을 보여준다.

```bash
whoami
tail -n 1 /var/log/agent-app/monitor.log
```

첫 줄의 결과는 `agent-admin`이다. 둘째 줄의 `tail`은 파일의 끝을 읽고, `-n 1`은 한 줄을 뜻한다. 실제 기록 한 줄은 이렇게 생겼다.

```text
[2026-11-19 03:15:02] PID:969 CPU:0.1% MEM:5.5% DISK_USED:3%
```

앞에서부터 측정 시각, 앱의 프로세스 번호(PID), 컴퓨터의 CPU·메모리·디스크 사용률이다. 지금 읽은 값은 예시와 달라도 된다.

## 긴 경로에 이름 붙이기

```bash
log_file=/var/log/agent-app/monitor.log
echo "$log_file"
tail -n 1 "$log_file"
```

첫 줄은 `log_file`이라는 변수에 경로를 저장한다. Bash에서는 대입할 때 `=` 양옆을 붙여 쓴다. 값을 꺼낼 때는 앞에 `$`를 붙인다. 큰따옴표는 값을 한 개의 인자로 전달하므로 경로에 공백이 들어가도 한 파일을 가리킨다.

## 여러 명령에 이름 붙이기

```bash
last_sample() {
    tail -n 1 "$1"
}

last_sample "$log_file"
```

중괄호 안에 명령을 적어 두면 **함수**가 된다. 빈 줄 다음의 `last_sample`에서 비로소 실행된다. 함수 안의 `$1`은 호출할 때 건넨 첫 번째 값이므로, 여기서는 로그 경로다. 이 함수는 방금 연 셸에서 연습용으로 만든 것이다.

```bash
sample="$(last_sample "$log_file")"
echo "$sample"
```

`$(명령)`은 그 명령이 화면에 출력할 내용을 받아 온다. 실제 스크립트도 `app_pid="$(find_app_pid)"`로 같은 일을 한다. 함수가 출력한 PID를 변수에 담아 나중에 로그에 쓴다.

다음은 같은 Ubuntu 셸에서 [앱과 포트 점검하기](02-health.md)다. 중간에 마치려면 `exit`로 Mac 터미널에 돌아간다.

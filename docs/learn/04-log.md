# 한 번의 점검을 매분 기록하기

## 한 줄만 쓰고 다음 줄 덧붙이기

Ubuntu의 `agent-admin` 셸에서 아래 명령을 실행한다.

```bash
practice_dir="$(mktemp -d)"
echo "첫 번째 점검" > "$practice_dir/example.log"
echo "두 번째 점검" >> "$practice_dir/example.log"
cat "$practice_dir/example.log"
```

`mktemp -d`는 이번 연습만의 빈 디렉토리를 만든다. `>`는 파일을 새로 쓰고 `>>`는 끝에 덧붙인다. 화면에 두 줄이 차례로 나오면 된다. 두 번째 `echo`에도 `>`를 썼다면 마지막 한 줄만 남았을 것이다.

## 실제 스크립트로 한 줄 만들기

```bash
AGENT_LOG_DIR="$practice_dir" "$AGENT_HOME/bin/monitor.sh"
echo "$?"
tail -n 1 "$practice_dir/monitor.log"
```

이번 한 번은 로그 경로만 연습 디렉토리로 바뀐다. 앱과 포트가 정상이면 종료 코드는 0이고, 마지막 명령은 시각·PID·CPU·MEM·DISK_USED가 들어 있는 새 줄을 보여준다. [monitor.sh](../../required/monitor.sh)의 `main`을 읽으면 방금 본 실행을 순서대로 따라갈 수 있다.

| 코드에서 찾을 함수 | 이 실습에서 본 동작 |
|---|---|
| `find_app_pid`, `check_port` | 앱 번호를 얻고, 포트가 연결을 기다리는지 확인한다. |
| `show_firewall_status` | 방화벽 상태를 화면에 표시한다. |
| `get_cpu_usage`, `get_mem_usage`, `get_disk_usage` | 로그에 넣을 숫자 세 개를 구한다. |
| `show_resources` | 숫자를 보여주고 기준을 넘으면 경고한다. |
| `append_log`, `rotate_log` | 다음 줄을 쓰면 10 MiB를 넘는지 검사하고 필요하면 파일을 교체한 뒤 한 줄을 덧붙인다. |

`append_log`에서 잠금을 거는 이유는 cron과 수동 실행이 우연히 겹칠 때 두 작업이 같은 로그를 동시에 교체하는 일을 막기 위해서다. 현재 파일 하나와 백업 아홉 개까지 보관한다.

## 누가 다음 점검을 실행할까?

```bash
crontab -l
tail -n 2 /var/log/agent-app/monitor.log
```

`crontab -l`은 현재 계정의 예약 목록을 보여준다. `* * * * *`로 시작하는 줄은 매분 `monitor.sh`를 실행한다. 뒤의 `>/dev/null 2>&1`은 화면에 보일 출력과 오류를 버린다. 스크립트가 파일에 직접 덧붙인 측정값은 남는다. 두 번째 명령의 시각을 보면 운영 로그가 언제 기록됐는지 알 수 있다.

## 보너스 · 내가 만든 한 줄로 통계 내기

```bash
AGENT_LOG_DIR="$practice_dir" "$AGENT_HOME/bin/report.sh"
```

점검을 한 번 했다면 `Data Points: 1`이다. 표본이 하나이므로 각 자원의 평균·최댓값·최솟값은 모두 같은 값이다. 두 번째 보너스인 `archive-logs.sh`는 오래된 로그를 압축하고 보관 기한이 지난 압축본을 지운다. [보너스 설명](../../bonus/README.md)에서 시험에 사용한 파일 나이와 예상 결과를 확인할 수 있다.

연습을 마치면 아래 명령으로 이번에 만든 파일을 치우고 Mac 터미널로 돌아간다.

```bash
rm -- "$practice_dir/example.log" "$practice_dir/monitor.log" "$practice_dir/.monitor.lock"
rmdir -- "$practice_dir"
exit
```

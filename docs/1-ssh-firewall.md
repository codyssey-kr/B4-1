# 1. SSH와 방화벽

목표: SSH 접속 포트를 20022로 바꾸고 root 원격 로그인을 막는다. 방화벽은 20022/tcp, 15034/tcp만 받는다.

## 알아야 할 것

- **SSH**: 다른 컴퓨터의 셸에 암호화된 연결로 접속하는 방법. 서버 쪽 프로그램은 `sshd`, 설정 파일은 `/etc/ssh/sshd_config`다.
- **포트**: 한 컴퓨터에서 통신하는 프로그램을 구분하는 번호(0~65535). SSH 기본값은 22다.
- **LISTEN**: 프로그램이 포트를 열고 접속을 기다리는 상태. `ss -tulnp`로 본다.
- **root**: 모든 권한을 가진 계정. 모든 리눅스에 같은 이름으로 있다.
- **방화벽**: 들어오는 연결을 규칙에 따라 허용하거나 차단한다. UFW는 Ubuntu의 방화벽 설정 도구다.
- LISTEN과 방화벽은 별개다. 프로그램이 LISTEN 중이어도 방화벽이 막으면 외부에서 접속할 수 없다.

## 왜 하는가

| 설정 | 막는 위협 | 한계 |
|---|---|---|
| 포트 22 → 20022 | 22번만 노리는 자동 스캔·비밀번호 대입 시도가 줄어든다 | 전체 포트 스캔으로 찾을 수 있어 단독 방어가 아니다 |
| `PermitRootLogin no` | 공격자는 계정 이름 `root`를 이미 알고 있다. 막으면 계정 이름부터 알아내야 하고, 일반 계정을 뚫어도 root 권한을 얻는 단계가 더 필요하다 | 일반 계정 비밀번호가 약하면 소용없다 |
| 방화벽 기본 차단 + 2개 허용 | 실수로 띄운 다른 프로그램이 외부에 노출되지 않는다 | 허용한 포트의 프로그램 취약점은 막지 못한다 |

root 직접 접속을 막으면 작업자는 자기 계정으로 들어온 뒤 `sudo`를 쓴다. 그래서 누가 작업했는지 기록이 남는다.

## 수행 (root 셸)

```sh
# SSH
sed -i -E 's/^#?[[:space:]]*Port[[:space:]].*/Port 20022/' /etc/ssh/sshd_config
sed -i -E 's/^#?[[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin no/' /etc/ssh/sshd_config
sshd -t                 # 문법 검사. 오류가 있으면 재시작하지 않는다
service ssh restart

# 방화벽
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw --force enable
```

원격 서버에서 작업한다면 순서를 지킨다: 방화벽에 20022 허용 → `sshd -t` → sshd 재시작 → **새 터미널**에서 20022 접속 확인. 순서가 틀리면 서버에 다시 접속할 수 없다.

## 확인

```sh
sshd -T | grep -E '^(port|permitrootlogin) '   # port 20022, permitrootlogin no
ss -tulnp | grep sshd                           # 0.0.0.0:20022 LISTEN
ufw status verbose                              # Status: active, 허용 규칙 2개
```

`sshd -T`는 설정 파일을 모두 읽은 뒤 실제로 적용되는 값을 출력한다. 파일을 `grep`하는 것보다 정확하다.

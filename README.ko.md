<h1 align="center">claw-vps</h1>

<p align="center">
  홈 서버를 위한 microVM — CLI 하나로, 진짜 KVM 격리
</p>

<p align="center">
  <a href="https://github.com/mir-stream/claw-vps/releases"><img src="https://img.shields.io/github/v/release/mir-stream/claw-vps?style=flat-square&color=blue" /></a>
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" />
  <img src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-lightgrey?style=flat-square" />
  <img src="https://img.shields.io/badge/firecracker-v1.16.0-orange?style=flat-square" />
</p>

<br>

```bash
sudo clawvps create bot1 --image openclaw --mem 2048
ssh root@10.42.0.10   # 노트북에서 — 15초 후 바로 접속
```

[English documentation](README.md)

---

## 왜

| | 컨테이너 | QEMU/KVM | Firecracker (claw-vps) |
|---|:---:|:---:|:---:|
| 커널 격리 | ❌ 공유 | ✅ | ✅ |
| 부팅 시간 | ~1s | 30s+ | **~1s** |
| VM당 오버헤드 | ~10 MB | 50 MB+ | **~5 MB** |
| 홈 서버에서 VM 수 | 많음 | 5–10개 | **50–100개** |

Firecracker는 AWS가 Lambda에서 실제로 쓰는 기술입니다. AI 에이전트를 각각 별도의 VM으로 감싸고, Tailscale을 통해 어디서든 SSH로 접속하고, Dockerfile로 이미지를 정의하세요.

> 홈랩 VPS로도 활용 가능합니다 — 클라우드 요금 없이 사이드 프로젝트를 배포하세요.

---

## 요구사항

- KVM이 활성화된 Linux (`ls /dev/kvm` 이 동작해야 함) — 베어 메탈 또는 중첩 가상화
- Ubuntu 24.04 권장 (Debian도 대체로 가능)
- [Tailscale](https://tailscale.com) 설치 및 로그인 완료 (무료 플랜)
- SSH 키 페어 — `clawvps init` 실행 중 공개키를 붙여넣어야 함. 이 키는 호스트가 아닌 **각 VM(게스트)** 에 주입됨. Tailscale SSH만 써서 키가 없다면 먼저 생성: `ssh-keygen -t ed25519`
- `docker` — 커스텀 이미지 빌드 시에만 필요

---

## 설치

```bash
# amd64
wget https://github.com/mir-stream/claw-vps/releases/download/v0.7.1/claw-vps_0.7.1_amd64.deb
sudo apt install ./claw-vps_0.7.1_amd64.deb

# arm64
wget https://github.com/mir-stream/claw-vps/releases/download/v0.7.1/claw-vps_0.7.1_arm64.deb
sudo apt install ./claw-vps_0.7.1_arm64.deb
```

최초 1회 설정:

```bash
sudo clawvps init          # VM subnet 광고 + SSH 키 등록
sudo clawvps setup kernel  # 게스트 커널 빌드 (5–40분, 최초 1회)
sudo clawvps setup base    # Ubuntu 24.04 기본 이미지 빌드
```

> `clawvps init` 실행 후, [Tailscale 관리 콘솔](https://login.tailscale.com/admin/machines) → 호스트 → Routing settings에서
> `10.42.0.0/16` subnet 라우트를 승인해야 합니다.

```bash
sudo clawvps create myvm    # "myvm" 은 그냥 VM 이름 — 원하는 이름으로
ssh root@10.42.0.10
```

---

## 커스텀 이미지

```bash
sudo clawvps build openclaw --example          # 번들 Dockerfile 사용
sudo clawvps build myapp -f myapp.Dockerfile   # 직접 작성한 Dockerfile 사용
sudo clawvps create bot1 --image openclaw --mem 2048
```

- `FROM claw-vps/base` 는 필수 — 일반 Ubuntu 이미지는 부팅되지 않음
- 서비스는 `RUN systemctl enable <unit>` 으로 등록 — `ENTRYPOINT`/`CMD` 는 무시됨
- 시크릿을 이미지에 넣지 말 것 — `clawvps create` 후 SSH로 주입할 것

---

## 일상 운영

```bash
clawvps list                # NAME IP STATE BOOT IMAGE CPU MEM
clawvps status bot1         # 단일 VM 상세 보기 + 최근 로그
clawvps images              # golden image + 커널 목록, 타임스탬프 포함
sudo clawvps logs bot1      # 시리얼 콘솔 — 부팅 실패 시 첫 번째 확인 지점
sudo clawvps stop bot1
sudo clawvps start bot1
sudo clawvps restart bot1
sudo clawvps destroy bot1   # 이름을 다시 입력해 확인; --force 로 생략 가능
```

VM은 **애완동물(pet)** 입니다 — `apt`, `npm` 등으로 인플레이스 업그레이드하세요. 게스트 안에서 `reboot`하거나 커널 패닉이 발생해도 systemd가 자동으로 복구합니다(`Restart=always`). 호스트 재부팅도 마찬가지로 모든 VM을 자동 복구합니다. VM을 내리려면 호스트에서 `sudo clawvps stop`을 쓰세요 — 이것이 정상적인 종료 경로입니다(게스트 안의 `poweroff`는 자동 재시작되므로 `clawvps stop`을 사용해야 합니다).

---

## 네트워크

```
  나 (tailnet 어디서든)
       │ ssh root@10.42.0.x
       ▼
  ┌──────────────────────────────┐
  │  홈 서버                     │
  │  ┌─────────┐  ┌─────────┐   │
  │  │ agent1  │  │ agent2  │   │
  │  │ microVM │  │ microVM │   │
  │  └────┬────┘  └────┬────┘   │
  │       └──── br0 ───┘        │
  └──────────────┬───────────────┘
                 ▼ NAT → 인터넷
```

| 방향 | 정책 |
|---|---|
| VM → 인터넷 | ✅ NAT |
| VM ↔ VM | ❌ 차단 |
| VM → 호스트 / LAN / tailnet | ❌ 차단 |
| tailnet → VM | ✅ subnet router |

VM은 tailnet에 직접 참여하지 않으며, 호스트가 subnet router 역할을 합니다. 각 VM은 최초 부팅 시 새로운 SSH host key와 machine-id를 발급받습니다.

---

## 트러블슈팅

**`Host key verification failed`** — VM destroy 후 IP가 재사용된 경우. 해결: `ssh-keygen -R <IP>`

**VM이 부팅되지 않음** — `sudo clawvps logs <name>` 으로 시리얼 콘솔 확인.

**노트북에서 VM에 접근 불가** — Tailscale 관리 콘솔에서 `10.42.0.0/16` 이 승인됐는지 확인.

**`clawvps build` 에서 docker 필요 오류** — `sudo apt install docker.io`

**`ls /dev/kvm` 실패** — KVM 없음. 하이퍼바이저에서 중첩 가상화 활성화 필요; Apple Silicon은 M3+ + macOS 15+ 필요.

---

## 소스에서 패키지 빌드

Linux에서 `dpkg-deb` 와 `curl` 이 필요합니다:

```bash
packaging/make-deb.sh                  # → packaging/dist/
VERSION=0.7.1 packaging/make-deb.sh
```

---

## 제거

```bash
sudo apt remove claw-vps   # 도구만 제거; VM은 재부팅 전까지 계속 실행됨
sudo apt purge claw-vps    # 설정 파일까지 정리
sudo rm -rf /var/lib/vms   # VM 데이터 삭제
```

---

## 로드맵

[BACKLOG.md](BACKLOG.md) — 다음 예정: `clawvps backup`, ttyd 웹 콘솔, Firecracker jailer, CoW 디스크.

---

## 라이선스

MIT. 번들된 Firecracker 바이너리는 Apache-2.0 라이선스 — LICENSE 및 NOTICE는 `/usr/share/doc/claw-vps/firecracker/` 에 있습니다.

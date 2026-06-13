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
# amd64 — 항상 최신 릴리스
wget https://github.com/mir-stream/claw-vps/releases/latest/download/claw-vps_amd64.deb
sudo apt install ./claw-vps_amd64.deb

# arm64 — 항상 최신 릴리스
wget https://github.com/mir-stream/claw-vps/releases/latest/download/claw-vps_arm64.deb
sudo apt install ./claw-vps_arm64.deb
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

## VM 생성

```bash
sudo clawvps create <name> [--image base] [--cpus 2] [--mem 1024] [--authkey-file <path>]
```

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `<name>` | — (필수) | 소문자/숫자/하이픈, 영숫자로 시작, **최대 11자** (tap 디바이스 제한) |
| `--image` | `base` | 복제할 golden image — `/var/lib/vms/images/<image>.ext4` (커스텀은 `clawvps build` 로 생성) |
| `--cpus` | `2` | vCPU 개수 |
| `--mem` | `1024` | 게스트 RAM, **MiB 단위** |
| `--authkey-file` | — | Tailscale authkey 파일; `/etc/vps/ts-authkey` (mode 600)로 주입돼 첫 부팅 때 한 번 tailnet 조인에 쓰이고 삭제됨 |

동작: 이미지를 VM의 rootfs로 sparse 복사하고, `10.42.0.10` 부터 다음 IP를 자동 할당(순차 증가 및 **단조** — VM을 destroy해도 IP를 재사용하지 않음)하며, hostname + networkd 설정을 주입한 뒤 systemd 슈퍼바이저로 부팅합니다.

```bash
sudo clawvps create myvm                          # base 이미지, 2 vCPU, 1024 MiB
sudo clawvps create bot1 --image openclaw --mem 2048
```

base 이미지와 게스트 커널이 있어야 합니다 (`clawvps setup base` / `clawvps setup kernel`).

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

## 메모리 오버커밋

VM은 게스트 RAM을 lazy하게 할당하므로, 호스트의 물리 RAM보다 더 많은 RAM을 여러 VM에
나눠줄 수 있습니다 — 대부분은 실제로 건드려지지 않습니다. 위험은 호스트가 Firecracker
프로세스를 OOM-kill 하는 것입니다. `clawvps tune` 은 표준 Linux 메커니즘 세 가지만으로
(커스텀 데몬 없음, Firecracker 전용 기능 없음) 오버커밋을 안전하게 만듭니다:

- `firecracker.slice` 에 호스트별 **`MemoryHigh` 소프트 캡** 적용 (모든 VM이 이 slice 안에서
  실행됨) — 메모리 압박 시 커널이 **VM들의** 페이지를 먼저 회수/스왑하므로 호스트 자체 RAM은
  보호됩니다;
- 호스트 **스왑파일** — `MemoryHigh` 가 차가운 게스트 페이지를 밀어낼 곳을 제공;
- **zswap** — 스왑 앞단의 압축 RAM 캐시로, 대부분의 회수가 SSD까지 가지 않게 함.

```bash
sudo clawvps tune          # 세 가지 모두 활성화 (권장)
```

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `--vm-mem-high` | `auto` | 모든 VM의 합산 소프트 캡. `auto` = 전체 RAM − 2048 MiB (호스트 여유분). systemd 크기 표기 가능 (`12G`, `8000M`). 호스트 RAM이 너무 적으면 경고 후 건너뜀. |
| `--swap` | `auto` | 호스트 스왑파일 크기. `auto` = 전체 RAM, 최대 16 GiB로 제한. `off` 면 스왑 생략. 크기 표기 가능 (`8G`). 기존 `/swapfile` 은 그대로 둠. |
| `--zswap` | `on` | 압축 스왑 캐시 활성화. `off` 면 생략. |

멱등(idempotent)하며(반복 실행 안전 — 캡 값은 갱신, 기존 스왑파일은 유지) systemd 유닛,
`/etc/fstab`, slice 드롭인으로 재부팅 후에도 유지됩니다 — GRUB이나 커널 cmdline은 절대
건드리지 않습니다.

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
packaging/make-deb.sh                  # → packaging/dist/ (버전은 make-deb.sh 기본값)
VERSION=x.y.z packaging/make-deb.sh    # 버전 직접 지정
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

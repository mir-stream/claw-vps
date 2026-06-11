# claw-vps

리눅스 머신 한 대에서 [Firecracker](https://firecracker-microvm.github.io/) microVM을
작은 VPS 업체처럼 찍어내는 도구 — UI 없이 CLI로.

```
sudo vm create bot1 --image openclaw --mem 2048
# 약 15초 뒤, tailnet의 아무 기기에서:
ssh root@10.42.0.10
```

[English documentation](README.md)

## 왜

자율 AI 에이전트(셸/파일/네트워크에 광범위하게 접근하는)를 집에서 믿지 않고 돌리기
위해 만들었다: 에이전트마다 컨테이너가 아닌 **진짜 KVM 가상머신** 안에서, 잠긴
네트워크와 함께 산다. VM은 [Tailscale](https://tailscale.com)을 통해 어디서든 접속
가능. VM당 오버헤드가 수 MB(Firecracker)라 작은 홈서버로도 여러 대를 돌릴 수 있다.

## 요구사항

- KVM 되는 리눅스 호스트: `ls /dev/kvm` 확인 (물리 머신, 또는 중첩 가상화 켠 VM).
  x86_64/arm64 모두 지원.
- Ubuntu 24.04에서 테스트됨 (Debian도 아마 동작).
- [Tailscale](https://tailscale.com) 계정 + 호스트에 tailscale 설치·로그인 (무료 플랜 OK).
- `docker` — 커스텀 이미지 빌드할 때만 (`sudo apt install docker.io`).
- 디스크: 1회성 빌드에 ~5 GB. 이미지는 16 GB *sparse* 파일 (실제 쓴 만큼만 차지).
- 주의: `vm setup kernel`은 리눅스 커널을 소스에서 컴파일한다. CPU에 따라
  5–40분 + 빌드 디렉토리 수 GB.

## 설치

아키텍처(amd64/arm64)에 맞는 `.deb`를 받아서:

```
sudo apt install ./claw-vps_<버전>_<아키>.deb

sudo vm init             # 1회: VM 대역 광고 + SSH 공개키 등록
sudo vm setup kernel     # 1회: 게스트 커널 빌드
sudo vm setup base       # 1회: 베이스 골든 이미지 (Ubuntu 24.04)

sudo vm create first     # VM 생성
```

`vm init` 마지막에 수동 작업이 하나 남는다: [Tailscale admin 콘솔](https://login.tailscale.com/admin/machines)에서
이 머신의 `10.42.0.0/16` 라우트 승인 (Machines → 호스트 → Routing settings).
그 후엔 tailnet의 아무 기기에서 VM IP로 바로 접속:

```
ssh root@10.42.0.10      # vm init 에서 등록한 키로 인증
```

## Dockerfile로 커스텀 이미지

agent 이미지는 평범한 Dockerfile로 정의한다. base 골든 이미지가 docker 이미지
`claw-vps/base`로 자동 import되고, 그 위에 얹은 결과가 부팅 가능한 디스크 이미지로
변환된다.

```
sudo vm build myagent                       # ./myagent.Dockerfile → ./Dockerfile 순으로 탐색
sudo vm build myagent -f ./my.Dockerfile    # 직접 지정
sudo vm build openclaw --example            # 동봉 예제 (examples/openclaw.Dockerfile)

sudo vm create bot1 --image myagent
```

규칙 (동봉 예제에도 주석으로 있음):

- `FROM claw-vps/base` 필수 — 일반 `ubuntu` 이미지는 systemd/sshd가 없어 VM으로 못 뜸
- `ENTRYPOINT`/`CMD`/`EXPOSE` 무시됨 — VM은 systemd로 부팅. 상시 서비스는
  `RUN systemctl enable <unit>`
- 비밀은 굽지 말 것 — `vm create` 후 SSH로 주입

## 일상 운영

```
vm list                  # NAME, IP, STATE, IMAGE, MEM
vm images                # 골든 이미지 + 커널, 타임스탬프
sudo vm logs bot1        # 시리얼 콘솔 (부팅 문제는 여기 봄)
sudo vm stop bot1 / sudo vm start bot1
sudo vm destroy bot1     # 이름 재입력 확인; 스크립트용 --force
```

- **VM은 애완동물(pet)**: 업그레이드는 VM *안에서* (`apt upgrade` 등).
  골든 이미지는 *새* VM의 시작점일 뿐.
- **호스트 재부팅**: 브리지·NAT·방화벽·VM 전부 systemd로 자동 복구.
- **패키지 업그레이드**: 동봉 `firecracker` 바이너리가 교체되지만, 실행 중 VM은
  stop/start 전까지 옛 바이너리로 돈다.

## 아키텍처

| 구성 | 위치 | 역할 |
|---|---|---|
| `vm` | `/usr/bin/vm` | CLI |
| `firecracker` | `/usr/sbin/firecracker` | 동봉 VMM (v1.16.0, Apache-2.0) |
| 게스트 커널 | `/var/lib/vms/kernel-claw` | 6.1.x, CI config + TUN/netfilter (`vm setup kernel`) |
| 골든 이미지 | `/var/lib/vms/images/*.ext4` | base + Dockerfile로 만든 이미지들 |
| VM별 상태 | `/var/lib/vms/<name>/` | rootfs.ext4, config.json, ip |
| `firecracker@.service` | `/lib/systemd/system/` | VM 1대 = 유닛 1개 (재부팅 영속) |
| `vps-network.service` | `/lib/systemd/system/` | 부팅 시 브리지+NAT+방화벽 |

네트워크: 브리지 하나(`br0`, `10.42.0.1/16`), VM당 tap 하나, IP는 `10.42.0.10`부터
자동 할당. 호스트가 서브넷 라우터로 tailnet에 광고하므로 VM은 Tailscale을 직접
돌리지 않는다.

### 격리 모델 (오작동하는 agent 봉쇄)

| 방향 | 정책 | 구현 |
|---|---|---|
| VM → 인터넷 | 허용 | NAT (MASQUERADE) |
| VM ↔ VM | 차단 | isolated bridge port (L2) + br0→br0 DROP (L3) |
| VM → 호스트 | 차단 | 전용 INPUT 체인 |
| VM → 집 LAN / tailnet | 차단 | RFC1918 + CGNAT 목적지 DROP |
| tailnet → VM | 허용 | 서브넷 라우터 인바운드 (SSH가 이 경로) |

클론마다 첫 부팅 때 SSH 호스트키와 machine-id를 재생성하므로 VM끼리 신원을
공유하지 않는다.

### 종료 시맨틱

- `vm stop`은 Firecracker API로 graceful shutdown 시도 (**x86_64 전용** —
  SendCtrlAltDel), 15초 후 SIGTERM. arm64는 항상 강제 종료.
- 게스트 안에서 `reboot`하면 Firecracker가 종료됨 — `vm start`로 다시 올림.

## 트러블슈팅

- **`Host key verification failed`** — destroy된 VM의 IP를 새 VM이 재사용한 것.
  해결: `ssh-keygen -R <IP>`
- **VM이 안 뜸** — `sudo vm logs <name>`에 시리얼 콘솔이 나온다.
- **노트북에서 VM에 접속 안 됨** — admin 콘솔에서 `10.42.0.0/16` 라우트가
  *승인*됐는지, 클라이언트가 tailnet에 붙어있는지 확인.
- **`vm build`가 docker를 요구** — `sudo apt install docker.io`
- **`ls /dev/kvm` 실패** — KVM 없음. VM 위라면 중첩 가상화 필요;
  Apple Silicon 맥은 M3 이상 + macOS 15 이상.

## 제거

```
sudo apt remove claw-vps     # 도구 제거; 실행 중 VM은 재부팅 전까지 돈다
sudo apt purge claw-vps      # 정리 포함; /var/lib/vms 의 VM 데이터는 보존됨
sudo rm -rf /var/lib/vms     # 정말 다 지우려면 직접
```

## 소스에서 패키지 빌드

리눅스에서 (`dpkg-deb`, `curl` 필요):

```
packaging/make-deb.sh                 # arm64 + amd64 deb → packaging/dist/
VERSION=0.5.0 packaging/make-deb.sh   # 버전 지정
```

## 로드맵

[BACKLOG.md](BACKLOG.md) 참고 — 주요 항목: `vm backup` (rootfs 스냅샷),
웹 시리얼 콘솔 (ttyd over tailnet), Firecracker jailer, CoW 디스크.

## 라이선스

MIT. deb에는 Firecracker 바이너리(Apache-2.0)가 동봉되며, 해당 LICENSE/NOTICE는
`/usr/share/doc/claw-vps/firecracker/`에 포함된다.

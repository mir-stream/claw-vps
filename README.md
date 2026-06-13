<h1 align="center">claw-vps</h1>

<p align="center">
  microVMs for your home server — one CLI, real KVM isolation
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
ssh root@10.42.0.10   # from your laptop — 15 seconds later
```

[한국어](README.ko.md)

---

## Why

| | Containers | QEMU/KVM | Firecracker (claw-vps) |
|---|:---:|:---:|:---:|
| Kernel isolation | ❌ shared | ✅ | ✅ |
| Boot time | ~1s | 30s+ | **~1s** |
| Overhead per VM | ~10 MB | 50 MB+ | **~5 MB** |
| VMs on a home server | many | 5–10 | **50–100** |

Firecracker is what AWS runs Lambda on. Wrap each AI agent in its own VM, SSH from anywhere via Tailscale, define images with Dockerfiles.

> Also works as a homelab VPS — deploy your vibe-coded side projects without a cloud bill.

---

## Requirements

- Linux with KVM (`ls /dev/kvm` must work) — bare metal or nested virt
- Ubuntu 24.04 (Debian likely fine)
- [Tailscale](https://tailscale.com) installed and logged in (free tier)
- An SSH key pair — `clawvps init` will prompt you to paste your public key; this key is injected into **every VM** (not the host). If you only use Tailscale SSH and have no key yet, generate one first: `ssh-keygen -t ed25519`
- `docker` — only for custom image builds

---

## Install

```bash
# amd64
wget https://github.com/mir-stream/claw-vps/releases/download/v0.7.1/claw-vps_0.7.1_amd64.deb
sudo apt install ./claw-vps_0.7.1_amd64.deb

# arm64
wget https://github.com/mir-stream/claw-vps/releases/download/v0.7.1/claw-vps_0.7.1_arm64.deb
sudo apt install ./claw-vps_0.7.1_arm64.deb
```

One-time setup:

```bash
sudo clawvps init          # advertise VM subnet + register your SSH key
sudo clawvps setup kernel  # build the guest kernel (5–40 min, once)
sudo clawvps setup base    # build the base Ubuntu 24.04 image
```

> After `clawvps init`, approve the `10.42.0.0/16` subnet route in the
> [Tailscale admin console](https://login.tailscale.com/admin/machines) → your host → Routing settings.

```bash
sudo clawvps create myvm    # "myvm" is just the name — pick anything
ssh root@10.42.0.10
```

---

## Custom images

```bash
sudo clawvps build openclaw --example          # use a bundled Dockerfile
sudo clawvps build myapp -f myapp.Dockerfile   # bring your own
sudo clawvps create bot1 --image openclaw --mem 2048
```

- `FROM claw-vps/base` is mandatory — plain Ubuntu images won't boot
- Register services with `RUN systemctl enable <unit>` — `ENTRYPOINT`/`CMD` are ignored
- Never bake secrets — inject over SSH after `clawvps create`

---

## Create a VM

```bash
sudo clawvps create <name> [--image base] [--cpus 2] [--mem 1024] [--authkey-file <path>]
```

| Option | Default | Notes |
|---|---|---|
| `<name>` | — (required) | lowercase letters/digits/hyphens, must start alnum, **max 11 chars** (tap-device limit) |
| `--image` | `base` | golden image to clone — `/var/lib/vms/images/<image>.ext4` (build custom ones with `clawvps build`) |
| `--cpus` | `2` | vCPU count |
| `--mem` | `1024` | guest RAM in **MiB** |
| `--authkey-file` | — | file holding a Tailscale authkey; injected as `/etc/vps/ts-authkey` (mode 600), used once on first boot to join the tailnet, then deleted |

What it does: sparse-copies the image to the VM's rootfs, auto-allocates the next IP from `10.42.0.10` upward (sequential and **monotonic** — destroying a VM never recycles its IP), injects hostname + networkd config, and boots it under the systemd supervisor.

```bash
sudo clawvps create myvm                          # base image, 2 vCPU, 1024 MiB
sudo clawvps create bot1 --image openclaw --mem 2048
```

Requires the base image and guest kernel (`clawvps setup base` / `clawvps setup kernel`).

---

## Operations

```bash
clawvps list                # NAME IP STATE BOOT IMAGE CPU MEM
clawvps status bot1         # detailed single-VM view + recent log tail
clawvps images              # golden images + kernel, with timestamps
sudo clawvps logs bot1      # serial console — first stop for boot failures
sudo clawvps stop bot1
sudo clawvps start bot1
sudo clawvps restart bot1
sudo clawvps destroy bot1   # re-type the name to confirm; --force skips it
```

VMs are **pets** — upgrade in-place with `apt`, `npm`, etc. The host supervisor owns
the VM lifecycle: host reboots, guest reboots, and kernel panics all auto-recover via
systemd. To take a VM down, use `sudo clawvps stop` on the host — that's the intended
power-down path (an in-guest `poweroff` will auto-restart instead).

---

## Network

```
  you (anywhere on tailnet)
       │ ssh root@10.42.0.x
       ▼
  ┌──────────────────────────────┐
  │  home server                 │
  │  ┌─────────┐  ┌─────────┐   │
  │  │ agent1  │  │ agent2  │   │
  │  │ microVM │  │ microVM │   │
  │  └────┬────┘  └────┬────┘   │
  │       └──── br0 ───┘        │
  └──────────────┬───────────────┘
                 ▼ NAT → internet
```

| Direction | Policy |
|---|---|
| VM → internet | ✅ NAT |
| VM ↔ VM | ❌ blocked |
| VM → host / LAN / tailnet | ❌ blocked |
| tailnet → VM | ✅ subnet router |

VMs don't join the tailnet — the host is the subnet router. Each VM gets fresh SSH host keys and machine-id on first boot.

---

## Troubleshooting

**`Host key verification failed`** — IP reused after destroy. Fix: `ssh-keygen -R <IP>`

**VM won't boot** — `sudo clawvps logs <name>` for the serial console.

**Can't reach VM from laptop** — check `10.42.0.0/16` is approved in Tailscale admin.

**`clawvps build` says docker required** — `sudo apt install docker.io`

**`ls /dev/kvm` fails** — no KVM. Enable nested virt in your hypervisor; on Apple Silicon requires M3+ + macOS 15+.

---

## Build from source

Needs `dpkg-deb` + `curl` on Linux:

```bash
packaging/make-deb.sh                  # → packaging/dist/
VERSION=0.7.1 packaging/make-deb.sh
```

---

## Uninstall

```bash
sudo apt remove claw-vps   # tool gone; VMs keep running until reboot
sudo apt purge claw-vps    # also cleans up
sudo rm -rf /var/lib/vms   # drop VM data
```

---

## Roadmap

[BACKLOG.md](BACKLOG.md) — next up: `clawvps backup`, ttyd web console, Firecracker jailer, CoW disks.

---

## License

MIT. Bundled Firecracker binary is Apache-2.0 — LICENSE + NOTICE at `/usr/share/doc/claw-vps/firecracker/`.

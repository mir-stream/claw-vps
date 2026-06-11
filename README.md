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
sudo vm create bot1 --image openclaw --mem 2048
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
- An SSH key pair on your local machine — `vm init` registers your public key into VMs
- `docker` — only for custom image builds

---

## Install

```bash
# amd64
wget https://github.com/mir-stream/claw-vps/releases/download/v0.4.0/claw-vps_0.4.0_amd64.deb
sudo apt install ./claw-vps_0.4.0_amd64.deb

# arm64
wget https://github.com/mir-stream/claw-vps/releases/download/v0.4.0/claw-vps_0.4.0_arm64.deb
sudo apt install ./claw-vps_0.4.0_arm64.deb
```

One-time setup:

```bash
sudo vm init          # advertise VM subnet + register your SSH key
sudo vm setup kernel  # build the guest kernel (5–40 min, once)
sudo vm setup base    # build the base Ubuntu 24.04 image
```

> After `vm init`, approve the `10.42.0.0/16` subnet route in the
> [Tailscale admin console](https://login.tailscale.com/admin/machines) → your host → Routing settings.

```bash
sudo vm create myvm    # "myvm" is just the name — pick anything
ssh root@10.42.0.10
```

---

## Custom images

```bash
sudo vm build openclaw --example          # use a bundled Dockerfile
sudo vm build myapp -f myapp.Dockerfile   # bring your own
sudo vm create bot1 --image openclaw --mem 2048
```

- `FROM claw-vps/base` is mandatory — plain Ubuntu images won't boot
- Register services with `RUN systemctl enable <unit>` — `ENTRYPOINT`/`CMD` are ignored
- Never bake secrets — inject over SSH after `vm create`

---

## Operations

```bash
vm list                # NAME IP STATE BOOT IMAGE CPU MEM
vm status bot1         # detailed single-VM view + recent log tail
vm images              # golden images + kernel, with timestamps
sudo vm logs bot1      # serial console — first stop for boot failures
sudo vm stop bot1
sudo vm start bot1
sudo vm restart bot1
sudo vm destroy bot1   # re-type the name to confirm; --force skips it
```

VMs are **pets** — upgrade in-place with `apt`, `npm`, etc. The host supervisor owns
the VM lifecycle: host reboots, guest reboots, and kernel panics all auto-recover via
systemd. To take a VM down, use `sudo vm stop` on the host — that's the intended
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

**VM won't boot** — `sudo vm logs <name>` for the serial console.

**Can't reach VM from laptop** — check `10.42.0.0/16` is approved in Tailscale admin.

**`vm build` says docker required** — `sudo apt install docker.io`

**`ls /dev/kvm` fails** — no KVM. Enable nested virt in your hypervisor; on Apple Silicon requires M3+ + macOS 15+.

---

## Build from source

Needs `dpkg-deb` + `curl` on Linux:

```bash
packaging/make-deb.sh                  # → packaging/dist/
VERSION=0.5.0 packaging/make-deb.sh
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

[BACKLOG.md](BACKLOG.md) — next up: `vm backup`, ttyd web console, Firecracker jailer, CoW disks.

---

## License

MIT. Bundled Firecracker binary is Apache-2.0 — LICENSE + NOTICE at `/usr/share/doc/claw-vps/firecracker/`.

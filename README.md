# claw-vps

Stamp out isolated [Firecracker](https://firecracker-microvm.github.io/) microVMs
on a single Linux box, like a tiny VPS provider — no UI, just a CLI.

```
sudo vm create bot1 --image openclaw --mem 2048
# ~15 seconds later, from any device on your tailnet:
ssh root@10.42.0.10
```

[한국어 문서](README.ko.md)

## Why

Built to run autonomous AI agents (with broad shell/file/network access) at home
without trusting them: each agent lives in a real KVM virtual machine with
hardware isolation and a locked-down network — not a container. VMs are
reachable from anywhere through your [Tailscale](https://tailscale.com) network.
Per-VM overhead is a few MB (Firecracker), so a small home server can run many.

## Requirements

- A Linux host with KVM: `ls /dev/kvm` must work (bare metal, or a VM with
  nested virtualization). x86_64 and arm64 are both supported.
- Ubuntu 24.04 is what the packages are tested on (Debian likely works).
- A [Tailscale](https://tailscale.com) account, with `tailscale` installed and
  logged in on the host (free tier is fine).
- `docker` — only if you build custom images (`sudo apt install docker.io`).
- Disk: ~5 GB for the one-time builds; images are 16 GB *sparse* files
  (they only consume what's actually written).
- Heads-up: `vm setup kernel` compiles a Linux kernel from source. Expect
  5–40 minutes depending on your CPU, and a few GB of build directory.

## Install

Grab the `.deb` for your architecture (amd64 / arm64), then:

```
sudo apt install ./claw-vps_<version>_<arch>.deb

sudo vm init             # one-time: advertise the VM subnet + register your SSH key
sudo vm setup kernel     # one-time: build the guest kernel
sudo vm setup base       # one-time: build the base golden image (Ubuntu 24.04)

sudo vm create first     # create a VM
```

`vm init` ends with one manual step: approve the `10.42.0.0/16` subnet route
for this machine in the [Tailscale admin console](https://login.tailscale.com/admin/machines)
(Machines → your host → Routing settings). After that, every VM is directly
reachable by IP from any device on your tailnet:

```
ssh root@10.42.0.10      # authenticated with the key you registered in vm init
```

## Custom images with Dockerfiles

Define agent images with a plain Dockerfile. The base golden image is
auto-imported as the docker image `claw-vps/base`; your Dockerfile layers on
top of it and the result is converted into a bootable disk image.

```
sudo vm build myagent                       # looks for ./myagent.Dockerfile, then ./Dockerfile
sudo vm build myagent -f ./my.Dockerfile    # explicit path
sudo vm build openclaw --example            # bundled example (examples/openclaw.Dockerfile)

sudo vm create bot1 --image myagent
```

Rules (also documented in the bundled example):

- `FROM claw-vps/base` is mandatory — plain `ubuntu` images can't boot as a VM
  (no systemd/sshd/network setup).
- `ENTRYPOINT`/`CMD`/`EXPOSE` are ignored — the VM boots with systemd. Register
  always-on services with `RUN systemctl enable <unit>`.
- Never bake secrets into images — inject them over SSH after `vm create`.

## Day-2 operations

```
vm list                  # NAME, IP, STATE, IMAGE, MEM
vm images                # golden images + kernel, with timestamps
sudo vm logs bot1        # follow the serial console (boot problems live here)
sudo vm stop bot1 / sudo vm start bot1
sudo vm destroy bot1     # asks you to re-type the name; --force for scripts
```

- **VMs are pets**: upgrade things *inside* the VM (`apt upgrade`, etc.).
  Golden images are only the starting point for *new* VMs.
- **Host reboot**: everything (bridge, NAT, firewall, VMs) comes back
  automatically via systemd.
- **Package upgrades**: a newer claw-vps deb replaces the bundled `firecracker`
  binary, but running VMs keep the old one until you stop/start them.

## Architecture

| Piece | Where | What |
|---|---|---|
| `vm` | `/usr/bin/vm` | the CLI |
| `firecracker` | `/usr/sbin/firecracker` | bundled VMM (v1.16.0, Apache-2.0) |
| guest kernel | `/var/lib/vms/kernel-claw` | 6.1.x, CI config + TUN/netfilter (built by `vm setup kernel`) |
| golden images | `/var/lib/vms/images/*.ext4` | base + your Dockerfile-built images |
| per-VM state | `/var/lib/vms/<name>/` | rootfs.ext4, config.json, ip |
| `firecracker@.service` | `/lib/systemd/system/` | one unit instance per VM (reboot persistence) |
| `vps-network.service` | `/lib/systemd/system/` | bridge + NAT + firewall at boot |

Networking: one bridge (`br0`, `10.42.0.1/16`), one tap device per VM, IPs
allocated from `10.42.0.10` upward. The host advertises the subnet to your
tailnet (subnet router), so VMs don't run Tailscale themselves.

### Isolation model (containing a misbehaving agent)

| Direction | Policy | Mechanism |
|---|---|---|
| VM → internet | allow | NAT (MASQUERADE) |
| VM ↔ VM | block | isolated bridge ports (L2) + br0→br0 DROP (L3) |
| VM → host | block | dedicated INPUT chain |
| VM → home LAN / tailnet | block | RFC1918 + CGNAT destination DROP |
| tailnet → VM | allow | subnet-router inbound (this is how you SSH in) |

Each clone regenerates its SSH host keys and machine-id on first boot, so VMs
don't share identity.

### Shutdown semantics

- `vm stop` attempts a graceful shutdown via the Firecracker API
  (**x86_64 only** — SendCtrlAltDel), then falls back to SIGTERM after 15s.
  On arm64 it's always a hard stop.
- `reboot` inside a guest exits Firecracker; the VM stays down until `vm start`.

## Troubleshooting

- **`Host key verification failed`** — a destroyed VM's IP was reused by a new
  VM. Fix: `ssh-keygen -R <IP>`.
- **VM won't boot** — `sudo vm logs <name>` shows the serial console.
- **Can't reach a VM from your laptop** — check that the `10.42.0.0/16` route
  is *approved* in the Tailscale admin console, and that your client is
  connected to the tailnet.
- **`vm build` says docker is required** — `sudo apt install docker.io`.
- **`ls /dev/kvm` fails** — no KVM. On a VM you need nested virtualization;
  on Apple Silicon Macs that means an M3+ host with macOS 15+.

## Uninstall

```
sudo apt remove claw-vps     # removes the tool; running VMs keep running until reboot
sudo apt purge claw-vps      # also runs cleanup; VM data in /var/lib/vms is kept
sudo rm -rf /var/lib/vms     # ...delete it explicitly if you really want it gone
```

## Building the package from source

On a Linux machine (needs `dpkg-deb`, `curl`):

```
packaging/make-deb.sh                 # builds arm64 + amd64 debs into packaging/dist/
VERSION=0.5.0 packaging/make-deb.sh   # override the version
```

## Roadmap

See [BACKLOG.md](BACKLOG.md) — highlights: `vm backup` (rootfs snapshots),
web serial console (ttyd over tailnet), Firecracker jailer, CoW disks.

## License

MIT. The deb bundles the Firecracker binary (Apache-2.0); its LICENSE and
NOTICE ship in `/usr/share/doc/claw-vps/firecracker/`.

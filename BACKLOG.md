# Backlog

Loosely prioritized. Items came out of design reviews; none block daily use.

## Next up

- **`clawvps backup <name>`** — snapshot a VM's rootfs.ext4 (sparse copy while
  stopped). The safety net for the pets model, where VMs are upgraded in place.
- **Web serial console** — browser ⇄ WebSocket gateway (ttyd) ⇄ Firecracker
  serial. The "console" button a real VPS provider has: access even when a
  guest's network is broken. Bind to the tailnet interface only. (Firecracker
  has no VNC/graphics, so a serial-based gateway is the right shape; noVNC
  does not apply.)
- **Release automation** — tag-triggered GitHub Action: build both debs with
  `VERSION` from the tag, upload as release assets.

## Robustness

- **Firecracker jailer** — run the VMM in a chroot as non-root (currently runs
  as root; a VMM escape today means root on the host).
- **IP allocation hardening** — reuse IPs freed by `clawvps destroy` (currently
  max+1, so freed IPs are stranded) and `flock` against concurrent
  `clawvps create` racing to the same IP/MAC.
- **Per-VM disk quotas** — a runaway guest can currently grow its sparse 16G
  rootfs until the host volume fills, taking down every VM.
- **CoW disks** — read-only base + per-VM overlay (or reflink/dm-thin) instead
  of full sparse copies; also reclaim freed guest blocks (no discard today).
- **Graceful guest shutdown on aarch64** — Firecracker has no `SendCtrlAltDel`
  on ARM, so every `clawvps stop`/`clawvps destroy`/host-maintenance stop hard-cuts the
  guest (systemd SIGTERMs firecracker; no guest filesystem flush — a durability
  risk for the rw ext4 rootfs). The `curl -f` change only removes the wasted
  ~10s wait, not the hard-cut. A real fix needs an in-guest agent (signal/vsock
  -triggered `poweroff`) or Firecracker ARM ACPI-shutdown support.

## Nice to have

- **`clawvps resize`** — grow a VM's disk/memory (disk: truncate + resize2fs;
  memory: edit config.json + restart).
- **Config injection via a second drive** (NoCloud style) instead of
  loop-mounting the rootfs at create time — removes mount-leak failure modes
  and would allow read-only base images.
- **Ephemeral, tagged authkeys** for the optional `--authkey-file` path
  (today a failed first boot leaves the key on disk and retries forever).

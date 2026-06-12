# Changelog

## 0.6.0 (2026-06-12)
- **Breaking: the CLI is renamed `vm` → `clawvps`.** The old generic `vm` command
  is gone; every invocation is now `clawvps <subcommand>` (e.g. `sudo clawvps create`,
  `clawvps list`, `clawvps logs`). The deb installs `/usr/bin/clawvps` and the
  `firecracker@.service` hooks call it. No `vm` shim is shipped — update any scripts,
  aliases, or muscle memory. VM data (`/var/lib/vms/`) and the `firecracker@<name>`
  unit naming are unchanged, so existing VMs keep running across the upgrade.

## 0.5.1 (2026-06-12)
- Non-disruptive upgrades: ship `/etc/needrestart/conf.d/claw-vps.conf` so Ubuntu's
  needrestart no longer auto-restarts running `firecracker@<vm>` units when the bundled
  firecracker binary is replaced on `apt`/`dpkg` upgrade (which hard-cut every guest).

## 0.5.0 (2026-06-12)
- New `clawvps restart <name>` and `clawvps status <name>` (detailed single-VM view: state,
  boot-enabled, PID, restart count, recent log tail). `clawvps list` gains CPU and BOOT
  columns.
- Restart policy changed to `Restart=always` so in-guest reboots and kernel panics
  auto-recover (firecracker exits 0 for all guest events, so `on-failure` never fired
  for a crash). `clawvps stop` is the intended power-down path; a boot-loop backstop
  (`StartLimitBurst`) prevents endless restarts on a VM that panics every boot.
- `send-shutdown` no longer stalls ~10s on aarch64 — curl `-f` short-circuits the
  unsupported SendCtrlAltDel (HTTP 400) instead of falling into the 10s wait loop.

## 0.4.0 (2026-06-11)
- Open-source release readiness: English CLI output and `clawvps help`, English-first
  README (Korean version in README.ko.md), MIT LICENSE, bundled Firecracker
  LICENSE/NOTICE in the deb, CHANGELOG, .gitignore.
- `make-deb.sh`: version overridable via `VERSION` env, optional `Homepage` field
  via `HOMEPAGE` env.

## 0.3.0 (2026-06-11)
- CLI verbs split: `clawvps setup kernel|base` (foundation) vs `clawvps build <image>`
  (Dockerfile only). `clawvps build` now looks for `./<image>.Dockerfile`, then
  `./Dockerfile`; `--example` selects a bundled example; `-f` specifies a file.

## 0.2.0 (2026-06-11)
- `clawvps init`: interactive one-time host setup (Tailscale subnet route + client
  SSH public key registration).
- Dockerfile-based image pipeline: base image auto-imported as docker image
  `claw-vps/base`; user Dockerfiles are built on top and converted to bootable
  ext4 images. OpenClaw becomes an example (`examples/openclaw.Dockerfile`).

## 0.1.2 (2026-06-11)
- `clawvps destroy` asks for name confirmation (`--force` to skip); input validation
  for `--mem`/`--cpus`; error messages include fix hints; new `clawvps images`,
  `clawvps version`, `clawvps help`; `clawvps list` gains IMAGE/MEM columns; `clawvps` moved to
  /usr/bin; postrm added; `iproute2` dependency declared.

## 0.1.0 (2026-06-11)
- First working package: `clawvps` CLI (create/list/start/stop/destroy/logs),
  Firecracker v1.16.0 bundled, bridge networking with full guest isolation,
  systemd units for reboot persistence, golden image build scripts.

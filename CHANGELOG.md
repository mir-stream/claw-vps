# Changelog

## 0.4.0 (2026-06-11)
- Open-source release readiness: English CLI output and `vm help`, English-first
  README (Korean version in README.ko.md), MIT LICENSE, bundled Firecracker
  LICENSE/NOTICE in the deb, CHANGELOG, .gitignore.
- `make-deb.sh`: version overridable via `VERSION` env, optional `Homepage` field
  via `HOMEPAGE` env.

## 0.3.0 (2026-06-11)
- CLI verbs split: `vm setup kernel|base` (foundation) vs `vm build <image>`
  (Dockerfile only). `vm build` now looks for `./<image>.Dockerfile`, then
  `./Dockerfile`; `--example` selects a bundled example; `-f` specifies a file.

## 0.2.0 (2026-06-11)
- `vm init`: interactive one-time host setup (Tailscale subnet route + client
  SSH public key registration).
- Dockerfile-based image pipeline: base image auto-imported as docker image
  `claw-vps/base`; user Dockerfiles are built on top and converted to bootable
  ext4 images. OpenClaw becomes an example (`examples/openclaw.Dockerfile`).

## 0.1.2 (2026-06-11)
- `vm destroy` asks for name confirmation (`--force` to skip); input validation
  for `--mem`/`--cpus`; error messages include fix hints; new `vm images`,
  `vm version`, `vm help`; `vm list` gains IMAGE/MEM columns; `vm` moved to
  /usr/bin; postrm added; `iproute2` dependency declared.

## 0.1.0 (2026-06-11)
- First working package: `vm` CLI (create/list/start/stop/destroy/logs),
  Firecracker v1.16.0 bundled, bridge networking with full guest isolation,
  systemd units for reboot persistence, golden image build scripts.

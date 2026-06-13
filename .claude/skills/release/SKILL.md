---
name: release
description: Cut and publish a new claw-vps release — verify the test suite (unit + E2E) is green on the build host, then bump the version, build the arm64+amd64 .deb packages on a Linux host, tag, and create a GitHub Release with the debs attached. Use when the user wants to "release", "publish", "ship", or "배포" a new claw-vps version, or asks to cut vX.Y.Z. A release is gated on E2E passing — never ship if E2E is red.
---

# Releasing claw-vps

claw-vps is distributed as `.deb` packages attached to GitHub Releases (there is no
apt repo). Users install with `sudo apt install ./claw-vps_<ver>_<arch>.deb`.

## Build/test host

The deb build and the E2E suite both run on a **separate Linux host you SSH to** —
`dpkg-deb` and the Firecracker microVM tests do not run on macOS. The host can be
**any architecture**: `make-deb.sh` downloads both the arm64 and amd64 firecracker
binaries, so a single Linux host of either arch produces **both** debs.

Set `HOST` to that host before running the steps below. The host must have:

- SSH reachability, and **root or passwordless `sudo`** (E2E needs root: firecracker,
  loop mounts, systemd). Build (`make-deb.sh`) and lint/unit need no root.
- `bats` + `shellcheck` installed (`sudo apt install -y bats shellcheck`) — the gate.
- Base image + guest kernel present (`clawvps images`; else `sudo clawvps setup base|kernel`).
- The host's own SSH key registered for host→guest SSH (see Step 0).

> The concrete address/credentials are environment-specific and change over time —
> keep them OUT of this file (it's a public repo); just set `HOST` before you start.

## Context / prerequisites

- **Repo:** `mir-stream/claw-vps` (releases are public).
- **`gh` CLI** must be authenticated locally with push/release rights to
  `mir-stream/claw-vps` (`gh auth status`).
- The build host may also run **production VMs**. Building debs does **not** touch them
  (and `make-deb.sh` needs no root). Do **not** `apt install` the freshly built deb on
  the build host as part of a release — releasing only publishes artifacts.
- **Tests gate the release.** The same host doubles as the E2E host. `unit` + `e2e`
  must be green before you bump a version (Step 0). E2E boots throwaway microVMs and
  does **not** touch production VMs.

## Steps

Set the version + host once:

```bash
VER=0.8.0                 # the new version
HOST=user@your-host       # Linux build/E2E host (root or passwordless sudo)
```

### 0. Gate — the test suite must pass (including E2E)

**No release proceeds unless `unit` + `e2e` are green on the host.** E2E actually boots
throwaway microVMs and asserts boot/SSH/lifecycle/isolation, so it is the only layer
that proves "it really works on a real host." It creates and destroys its own
`bt*`/`bia*`/`m*` VMs and never touches production VMs.

Sync the working tree to the host and run the layers. A *relative* `claw-vps-src` dest
lands in the SSH user's home, so this works whether `HOST` is `root@…` or `user@…`:

```bash
rsync -az --delete --exclude='.git' --exclude='packaging/dist' --exclude='.idea' ./ "$HOST:claw-vps-src/"
ssh "$HOST" "cd claw-vps-src && chmod +x clawvps tests/run-tests.sh && tests/run-tests.sh lint && tests/run-tests.sh unit && sudo tests/run-tests.sh e2e"
```

`unit` + `e2e` must exit 0. If any test fails or is unexpectedly **skipped**
(a skip means a prerequisite is missing, not that it passed), **stop — do not
release.** One-time host setup if E2E skips:

- `sudo apt install -y bats shellcheck`.
- base image + guest kernel present (`clawvps images`); else `sudo clawvps setup base|kernel`.
- the **host's own** SSH key must be registered so host→guest SSH works:
  `ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519` (use `/root/.ssh/…` if `HOST` is
  root), then append the `.pub` to `/var/lib/vms/authorized_keys` (or `sudo clawvps init`).
  Without it every reachability/isolation test times out.
- `LAN_TARGET=<a private IP the host can reach, e.g. its gateway>` makes the
  VM→home-LAN block assertion run live instead of skipping (optional but preferred).

Lint (`tests/run-tests.sh lint`) is advisory: it currently surfaces only
pre-existing style infos (SC2012/SC2119/SC2120) and exits non-zero, so it is **not**
part of the hard gate — run it, read it, but it does not block the release.

### 1. Bump version + changelog, commit, push

- Edit `packaging/make-deb.sh`: default `VERSION="${VERSION:-<VER>}"`.
- Add a `## <VER> (YYYY-MM-DD)` section to `CHANGELOG.md` (today's date).
- Commit (include any feature changes) and push to `main`.

```bash
git add packaging/make-deb.sh CHANGELOG.md <other changed files>
git commit -m "claw-vps $VER — <summary>"
git push
```

### 2. Tag and push the tag

```bash
git tag -a "v$VER" -m "claw-vps $VER"
git push origin "v$VER"
```

### 3. Build both debs on the Linux host

Sync the working tree (which must equal the committed state) and build (no root needed):

```bash
rsync -az --delete --exclude='.git' --exclude='packaging/dist' --exclude='.idea' ./ "$HOST:claw-vps-src/"
ssh "$HOST" "cd claw-vps-src && VERSION=$VER bash packaging/make-deb.sh"
ssh "$HOST" "sha256sum claw-vps-src/packaging/dist/claw-vps_${VER}_*.deb"
```

Output: `packaging/dist/claw-vps_<VER>_arm64.deb` and `..._amd64.deb`.
(`make-deb.sh` is invoked with `bash` because rsync may drop the execute bit.)

### 4. Fetch debs to local, verify checksums

```bash
mkdir -p "$TMPDIR/claw-rel"
scp "$HOST:claw-vps-src/packaging/dist/claw-vps_${VER}_arm64.deb" \
    "$HOST:claw-vps-src/packaging/dist/claw-vps_${VER}_amd64.deb" "$TMPDIR/claw-rel/"
( cd "$TMPDIR/claw-rel" && shasum -a 256 *.deb )   # must match the host sha256sum

# Version-less copies so the README can use a never-stale download URL
# (github.com/.../releases/latest/download/claw-vps_<arch>.deb). Same bytes,
# stable name — keep the versioned debs too for history.
cp "$TMPDIR/claw-rel/claw-vps_${VER}_amd64.deb" "$TMPDIR/claw-rel/claw-vps_amd64.deb"
cp "$TMPDIR/claw-rel/claw-vps_${VER}_arm64.deb" "$TMPDIR/claw-rel/claw-vps_arm64.deb"
```

### 5. Create the GitHub Release with both debs

Notes should include the new `CHANGELOG.md` section plus the install one-liner.
Attach **four** assets: the versioned debs (history) plus the version-less copies
(so `releases/latest/download/claw-vps_<arch>.deb` — the README install URL — works).

```bash
cd "$TMPDIR/claw-rel"
gh release create "v$VER" \
  "claw-vps_${VER}_arm64.deb" "claw-vps_${VER}_amd64.deb" \
  "claw-vps_arm64.deb" "claw-vps_amd64.deb" \
  --repo mir-stream/claw-vps \
  --title "claw-vps $VER" \
  --notes "$(printf '...install instructions + changelog...')"
gh release view "v$VER" --repo mir-stream/claw-vps --json url,assets \
  --jq '{url, assets:[.assets[].name]}'
```

### 6. Clean up build artifacts

```bash
rm -rf "$TMPDIR/claw-rel"
ssh "$HOST" "rm -rf claw-vps-src"
```

## Notes

- Since **0.5.1**, the deb ships `/etc/needrestart/conf.d/claw-vps.conf`, so
  `apt install` of a new deb on Ubuntu does **not** bounce running
  `firecracker@<vm>` VMs (needrestart defers them, like docker/dbus). Upgrades
  are non-disruptive; running VMs keep their PID.
- Installing a deb only registers an upgrade if the version is **higher** than
  what is installed — always bump `VER` (and the `make-deb.sh` default) first.
- VM data (`/var/lib/vms/`) is never part of the deb, so upgrades never touch
  disks/images/config.
- **Never ship past a red E2E.** If you changed `clawvps`, the build/setup scripts, or
  networking, re-run Step 0 — unit tests alone do not prove a guest still boots,
  stays reachable, or remains isolated. E2E is slow on purpose; that is the cost
  of confidence before a public release.
- This is the manual flow. Automating it (tag → GitHub Action builds + uploads,
  with the E2E gate as a required check) is a standing backlog item; until then,
  run these steps by hand.

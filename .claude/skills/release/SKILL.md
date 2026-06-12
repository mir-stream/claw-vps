---
name: release
description: Cut and publish a new claw-vps release — bump the version, build the arm64+amd64 .deb packages on a Linux host, tag, and create a GitHub Release with the debs attached. Use when the user wants to "release", "publish", "ship", or "배포" a new claw-vps version, or asks to cut vX.Y.Z.
---

# Releasing claw-vps

claw-vps is distributed as `.deb` packages attached to GitHub Releases (there is no
apt repo). Users install with `sudo apt install ./claw-vps_<ver>_<arch>.deb`.

## Context / prerequisites

- **Repo:** `mir-stream/claw-vps` (releases are public).
- **deb build needs Linux** — `dpkg-deb` does not run on macOS. Build on an
  aarch64 Linux host you can ssh to. Current host: `root@100.106.44.11`
  (homelab M4 Mac mini, Ubuntu aarch64, reachable over Tailscale). One
  `make-deb.sh` run produces **both** `arm64` and `amd64` debs (it downloads the
  matching firecracker binaries), so a single aarch64 host covers both arches.
- **`gh` CLI** must be authenticated locally as a user with push/release rights
  (`gh auth status` → account `mir-stream`).
- The build host may run **production VMs** (e.g. `claw1`). Building debs does
  **not** touch them. Do **not** `apt install` on the build host as part of a
  release — releasing only publishes artifacts.

## Steps

Set the version once:

```bash
VER=0.5.2                      # the new version
HOST=root@100.106.44.11        # aarch64 Linux build host
```

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

Sync the working tree (which must equal the committed state) and build:

```bash
rsync -az --delete --exclude='.git' --exclude='packaging/dist' ./ "$HOST:/root/claw-vps-src/"
ssh "$HOST" "cd /root/claw-vps-src && VERSION=$VER bash packaging/make-deb.sh"
ssh "$HOST" "sha256sum /root/claw-vps-src/packaging/dist/claw-vps_${VER}_*.deb"
```

Output: `packaging/dist/claw-vps_<VER>_arm64.deb` and `..._amd64.deb`.
(`make-deb.sh` is invoked with `bash` because rsync may drop the execute bit.)

### 4. Fetch debs to local, verify checksums

```bash
mkdir -p "$TMPDIR/claw-rel"
scp "$HOST:/root/claw-vps-src/packaging/dist/claw-vps_${VER}_arm64.deb" \
    "$HOST:/root/claw-vps-src/packaging/dist/claw-vps_${VER}_amd64.deb" "$TMPDIR/claw-rel/"
( cd "$TMPDIR/claw-rel" && shasum -a 256 *.deb )   # must match the host sha256sum
```

### 5. Create the GitHub Release with both debs

Notes should include the new `CHANGELOG.md` section plus the install one-liner.

```bash
cd "$TMPDIR/claw-rel"
gh release create "v$VER" \
  "claw-vps_${VER}_arm64.deb" "claw-vps_${VER}_amd64.deb" \
  --repo mir-stream/claw-vps \
  --title "claw-vps $VER" \
  --notes "$(printf '...install instructions + changelog...')"
gh release view "v$VER" --repo mir-stream/claw-vps --json url,assets \
  --jq '{url, assets:[.assets[].name]}'
```

### 6. Clean up build artifacts

```bash
rm -rf "$TMPDIR/claw-rel"
ssh "$HOST" "rm -rf /root/claw-vps-src"
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
- This is the manual flow. Automating it (tag → GitHub Action builds + uploads)
  is a standing backlog item; until then, run these steps by hand.

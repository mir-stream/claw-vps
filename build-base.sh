#!/usr/bin/env bash
# build-base.sh — bake the "bare VPS" base golden image (invoked as: vm setup base)
# Baked in:  Ubuntu 24.04 + sshd + Tailscale + serial autologin + networkd +
#            a first-boot unit (vps-firstboot).
# NOT baked: IP / hostname / Tailscale authkey — `vm create` injects those per clone.
# Agents aren't baked either — define them with Dockerfiles (vm build).
# Output: /var/lib/vms/images/base.ext4
set -euo pipefail

IMG="/var/lib/vms/images/base.ext4"
SIZE="16G"
MNT="$(mktemp -d /mnt/vps-build.XXXX)"
SUITE="noble"
MIRROR="http://ports.ubuntu.com/ubuntu-ports/"   # arm64 mirror; swapped below on x86_64
[ "$(uname -m)" = "x86_64" ] && MIRROR="http://archive.ubuntu.com/ubuntu/"

[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
command -v debootstrap >/dev/null || { echo "debootstrap required (apt install -y debootstrap)" >&2; exit 1; }

cleanup() {
  set +e
  for d in dev/pts dev proc sys; do mountpoint -q "${MNT}/${d}" && umount "${MNT}/${d}"; done
  mountpoint -q "${MNT}" && umount "${MNT}"
  rmdir "${MNT}" 2>/dev/null
}
trap cleanup EXIT

echo "==> 1. creating and mounting an empty ext4 image"
mkdir -p "$(dirname "${IMG}")"
[ -f "${IMG}" ] && mv -v "${IMG}" "${IMG}.bak"
truncate -s "${SIZE}" "${IMG}"
mkfs.ext4 -q "${IMG}"
mount -o loop "${IMG}" "${MNT}"
mountpoint -q "${MNT}" || { echo "ERROR: mount failed — aborting." >&2; exit 1; }

echo "==> 2. debootstrap (${SUITE})"
debootstrap --include=systemd,systemd-sysv,iproute2,iputils-ping,curl,ca-certificates,nano,sudo,xz-utils,gnupg \
  "${SUITE}" "${MNT}" "${MIRROR}"

echo "==> 3. preparing chroot (binds + DNS + blocking service autostart)"
mount --bind /dev      "${MNT}/dev"
mount --bind /dev/pts  "${MNT}/dev/pts"
mount --bind /proc     "${MNT}/proc"
mount --bind /sys      "${MNT}/sys"
echo "nameserver 8.8.8.8" > "${MNT}/etc/resolv.conf"
# Prevent package postinst scripts from trying (and failing) to start services in the chroot.
printf '#!/bin/sh\nexit 101\n' > "${MNT}/usr/sbin/policy-rc.d"
chmod +x "${MNT}/usr/sbin/policy-rc.d"

echo "==> 4. configuring inside the chroot"
chroot "${MNT}" /bin/bash -euo pipefail <<CHROOT
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y openssh-server iptables

echo "vps-base" > /etc/hostname

# Serial-console autologin. Console name differs by arch, so cover both.
for tty in ttyS0 ttyAMA0; do
  mkdir -p /etc/systemd/system/serial-getty@\${tty}.service.d
  cat > /etc/systemd/system/serial-getty@\${tty}.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --keep-baud 115200,38400,9600 \${tty} \\\$TERM
EOF
done

# Networking: enable networkd only; the per-VM eth0 config is injected by `vm create`
# (kernel ip= boot args don't work with this kernel config — networkd does).
systemctl enable systemd-networkd
systemctl enable ssh

# Tailscale (add the apt repo directly; install.sh would try `systemctl --now` in chroot)
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/${SUITE}.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/${SUITE}.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y tailscale
systemctl enable tailscaled

# Pin iptables to the legacy backend (tailscale's nft autodetection misfires in
# minimal guests; legacy is reliable with this kernel config).
update-alternatives --set iptables  /usr/sbin/iptables-legacy   || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy  || true

apt-get clean
rm -rf /var/lib/apt/lists/*

# Strip SSH host keys and machine-id from the golden image — otherwise every
# clone shares the same identity (a hostile VM could impersonate its siblings).
# Each clone regenerates these on first boot.
rm -f /etc/ssh/ssh_host_*
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Regenerate SSH host keys on first boot (before sshd starts).
cat > /etc/systemd/system/regen-ssh-hostkeys.service <<'EOF'
[Unit]
Description=Regenerate SSH host keys on first boot
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOF
systemctl enable regen-ssh-hostkeys.service
CHROOT

echo "==> 5. installing the first-boot unit (joins the tailnet if vm create injected an authkey)"
cat > "${MNT}/usr/local/sbin/vps-firstboot" <<'EOF'
#!/usr/bin/env bash
# Runs once if /etc/vps/ts-authkey exists: join the tailnet (+SSH), then discard the key.
set -euo pipefail
KEYFILE="/etc/vps/ts-authkey"
[ -f "${KEYFILE}" ] || exit 0
AUTHKEY="$(cat "${KEYFILE}")"
tailscale up --authkey="${AUTHKEY}" --ssh --hostname="$(hostname)"
rm -f "${KEYFILE}"
echo "vps-firstboot: tailscale up done ($(tailscale ip -4 2>/dev/null || echo '?'))"
EOF
chmod +x "${MNT}/usr/local/sbin/vps-firstboot"

cat > "${MNT}/etc/systemd/system/vps-firstboot.service" <<'EOF'
[Unit]
Description=VPS first-boot provisioning (tailscale join)
After=network-online.target tailscaled.service
Wants=network-online.target
ConditionPathExists=/etc/vps/ts-authkey

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vps-firstboot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
ln -sf /etc/systemd/system/vps-firstboot.service \
  "${MNT}/etc/systemd/system/multi-user.target.wants/vps-firstboot.service"

rm -f "${MNT}/usr/sbin/policy-rc.d"

echo "==> done: ${IMG}"

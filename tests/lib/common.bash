# Shared helpers for E2E bats tests. Sourced via `load` from each .bats file.
#
# E2E tests run ON the host VM (need root, firecracker, systemd, loop mounts).
# By default they exercise the WORKING-TREE `vm` script — so you test the change
# you're about to ship, against the base image / kernel already in /var/lib/vms.
#   Override the binary under test: VM_BIN=vm tests/run-tests.sh e2e   (installed deb)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VM_BIN="${VM_BIN:-$REPO_ROOT/vm}"
VMROOT="${VMROOT:-/var/lib/vms}"

# Optional private-LAN target for the isolation test (VM → home LAN must be
# blocked). Unset → that test skips. Set e.g. LAN_TARGET=192.168.1.1.
LAN_TARGET="${LAN_TARGET:-}"

# Run the CLI under test as root.
vm_cli() { sudo "$VM_BIN" "$@"; }

# Skip the test unless we can actually drive a real host.
require_host() {
  command -v firecracker >/dev/null 2>&1 || skip "firecracker not installed — E2E needs a configured host"
  sudo -n true 2>/dev/null || skip "passwordless sudo required for E2E (or run the suite as root)"
  [ -f "$VMROOT/images/base.ext4" ] || skip "base image missing — run: sudo vm setup base"
  [ -f "$VMROOT/kernel-claw" ]      || skip "guest kernel missing — run: sudo vm setup kernel"
}

# A short, valid VM name (<=11 chars per the tap-device limit). $BATS_TEST_NUMBER
# keeps names distinct within a file; teardown destroys whatever we created.
test_vm_name() { echo "bt${BATS_TEST_NUMBER}$$" | cut -c1-11; }

vm_ip() { cat "$VMROOT/$1/ip" 2>/dev/null; }

# Poll SSH until the guest answers or we time out. The VM boots async, so every
# reachability assertion must wait rather than probe once.
wait_for_ssh() {
  local ip="$1" timeout="${2:-90}" i=0
  while [ "$i" -lt "$timeout" ]; do
    if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=3 "root@$ip" true 2>/dev/null; then
      return 0
    fi
    sleep 1; i=$((i + 1))
  done
  return 1
}

guest_ssh() {
  local ip="$1"; shift
  # LogLevel=ERROR silences "Warning: Permanently added ... known hosts" — bats `run`
  # merges stderr into $output, so without this it pollutes output-equality asserts.
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR -o ConnectTimeout=5 "root@$ip" "$@"
}

destroy_quietly() { vm_cli destroy "$1" --force >/dev/null 2>&1 || true; }

# Path to a VM's firecracker config.json.
config_json() { echo "$VMROOT/$1/config.json"; }

# Inspect a VM's rootfs without racing the running RW image: stop the VM (release
# the loop file), mount it read-only, hand the mountpoint to a callback, then
# ALWAYS unmount + rmdir (even if the callback's asserts fail and abort the test).
inspect_rootfs() {
  local name="$1" callback="$2" mnt status
  vm_cli stop "$name" >/dev/null 2>&1 || true
  mnt="$(mktemp -d)"
  sudo mount -o loop,ro,norecovery "$VMROOT/$name/rootfs.ext4" "$mnt" \
    || { rmdir "$mnt"; echo "inspect_rootfs: mount failed for $name" >&2; return 1; }
  # Run the callback in a way that we can always clean up after it.
  status=0
  "$callback" "$mnt" || status=$?
  sudo umount "$mnt" 2>/dev/null || true
  rmdir "$mnt" 2>/dev/null || true
  return "$status"
}

# Run a ping from inside the guest; return its exit status (0 = reachable).
guest_ping() {
  local ip="$1" target="$2"
  guest_ssh "$ip" "ping -c1 -W2 $target"
}

# Does the host itself have internet? Gates the VM→internet allow test.
host_has_internet() { ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; }

#!/usr/bin/env bats
# L3 injection verification: after `clawvps create`, check the per-VM artifacts WITHOUT
# waiting for the guest to boot/SSH — purely deterministic. We assert on
# config.json (no mount) and, via a read-only loop mount of rootfs.ext4, the files
# injected into the guest. This is the fastest, most stable regression net.
#
# IPs are NOT predictable (the host may already run real VMs), so we read the
# actually-allocated IP from $VMROOT/<name>/ip and assert against THAT value.

load ../lib/common.bash

setup() {
  require_host
  # Reuse the real mac_for_ip from the script under test (cross-checks that the
  # MAC we expect matches the code that produced it, not a duplicated constant).
  # shellcheck source=/dev/null
  source "$VM_BIN"
  NAME="$(test_vm_name)"
  destroy_quietly "$NAME"
}

teardown() {
  [ -n "${NAME:-}" ] && destroy_quietly "$NAME"
}

@test "inject: config.json carries the cpu/mem/mac/tap we asked for" {
  run vm_cli create "$NAME" --cpus 3 --mem 777
  [ "$status" -eq 0 ]

  local cfg ip
  cfg="$(config_json "$NAME")"
  ip="$(vm_ip "$NAME")"
  [ -n "$ip" ]

  run sudo grep -q '"vcpu_count": 3' "$cfg";       [ "$status" -eq 0 ]
  run sudo grep -q '"mem_size_mib": 777' "$cfg";   [ "$status" -eq 0 ]
  run sudo grep -q "\"host_dev_name\": \"tap-$NAME\"" "$cfg"; [ "$status" -eq 0 ]

  # MAC must equal what the real helper computes for the allocated IP.
  local expected_mac
  expected_mac="$(mac_for_ip "$ip")"
  run sudo grep -q "\"guest_mac\": \"$expected_mac\"" "$cfg"
  [ "$status" -eq 0 ]
}

@test "inject: rootfs gets hostname + networkd config for the allocated IP" {
  vm_cli create "$NAME"
  local ip
  ip="$(vm_ip "$NAME")"
  [ -n "$ip" ]
  export NAME IP="$ip"

  _check() {
    local mnt="$1"
    [ "$(sudo cat "$mnt/etc/hostname")" = "$NAME" ]
    sudo grep -q "Address=$IP/16" "$mnt/etc/systemd/network/10-eth0.network"
    sudo grep -q "Gateway=10.42.0.1" "$mnt/etc/systemd/network/10-eth0.network"
    # If the host registered a client key, it must land in the guest.
    if [ -f "$VMROOT/authorized_keys" ]; then
      sudo test -f "$mnt/root/.ssh/authorized_keys"
    fi
  }
  inspect_rootfs "$NAME" _check
}

@test "inject: --authkey-file installs /etc/vps/ts-authkey mode 600" {
  local keyfile
  keyfile="$(mktemp)"
  echo "tskey-test-deadbeef" > "$keyfile"

  vm_cli create "$NAME" --authkey-file "$keyfile"
  rm -f "$keyfile"

  _check_authkey() {
    local mnt="$1"
    sudo test -f "$mnt/etc/vps/ts-authkey"
    local mode
    mode="$(sudo stat -c '%a' "$mnt/etc/vps/ts-authkey")"
    [ "$mode" = "600" ]
  }
  inspect_rootfs "$NAME" _check_authkey
}

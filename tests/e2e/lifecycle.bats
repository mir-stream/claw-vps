#!/usr/bin/env bats
# Full-lifecycle E2E against the working-tree `vm`. This is the real regression
# net: a VM is actually created, booted, reached over SSH, restarted, recovered,
# and destroyed — with host-side cleanup verified. Minutes, not seconds.

load ../lib/common.bash

# Extra VMs some tests create beyond $NAME; teardown cleans these even on abort.
EXTRA_VMS=""

setup() {
  require_host
  NAME="$(test_vm_name)"
  destroy_quietly "$NAME"   # clear any leftover from a previous aborted run
}

teardown() {
  [ -n "${NAME:-}" ] && destroy_quietly "$NAME"
  for v in ${EXTRA_VMS:-}; do destroy_quietly "$v"; done
}

@test "create: VM appears running in 'vm list' with an allocated IP" {
  run vm_cli create "$NAME"
  [ "$status" -eq 0 ]

  run vm_cli list
  [[ "$output" == *"$NAME"* ]]
  [[ "$output" == *"active"* ]]

  ip="$(vm_ip "$NAME")"
  [[ "$ip" == 10.42.0.* ]]
}

@test "create: guest boots and is reachable over SSH with the right hostname" {
  vm_cli create "$NAME"
  ip="$(vm_ip "$NAME")"

  wait_for_ssh "$ip" || { vm_cli logs "$NAME" 2>/dev/null | tail -40; false; }

  run guest_ssh "$ip" hostname
  [ "$status" -eq 0 ]
  [ "$output" = "$NAME" ]
}

@test "status: reports the VM as active with its IP" {
  vm_cli create "$NAME"
  run vm_cli status "$NAME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$NAME"* ]]
  [[ "$output" == *"active"* ]]
}

@test "restart: VM comes back up and is reachable again" {
  vm_cli create "$NAME"
  ip="$(vm_ip "$NAME")"
  wait_for_ssh "$ip"

  run vm_cli restart "$NAME"
  [ "$status" -eq 0 ]
  wait_for_ssh "$ip" || { vm_cli logs "$NAME" 2>/dev/null | tail -40; false; }
}

@test "recovery: an in-guest reboot auto-recovers (Restart=always)" {
  vm_cli create "$NAME"
  ip="$(vm_ip "$NAME")"
  wait_for_ssh "$ip"

  # `reboot` exits firecracker 0; systemd must bring it straight back.
  guest_ssh "$ip" "nohup reboot >/dev/null 2>&1 &" || true
  sleep 5   # let it actually go down before we wait for it to return
  wait_for_ssh "$ip" 120 || { vm_cli logs "$NAME" 2>/dev/null | tail -40; false; }
}

@test "destroy: removes the VM dir and tears down its tap device" {
  local gone="$NAME"
  vm_cli create "$gone"
  [ -f "$VMROOT/$gone/config.json" ]

  run vm_cli destroy "$gone" --force
  [ "$status" -eq 0 ]
  NAME=""   # already destroyed; nothing for teardown to clean

  run sudo test -e "$VMROOT/$gone"
  [ "$status" -ne 0 ]
  # tap device must be gone too (cmd_net_down)
  run ip link show "tap-$gone"
  [ "$status" -ne 0 ]
}

@test "create: a second VM with the same name is rejected" {
  vm_cli create "$NAME"
  run vm_cli create "$NAME"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "create: failure mid-build cleans up the half-built VM dir (no IP leak)" {
  # --authkey-file points at a missing path: create fails AFTER the dir + ip file
  # are written, so the EXIT trap (_create_cleanup) must remove the whole dir.
  run vm_cli create "$NAME" --authkey-file /nonexistent/key
  [ "$status" -ne 0 ]

  run sudo test -e "$VMROOT/$NAME"
  [ "$status" -ne 0 ]   # nothing left behind to poison next_ip
  NAME=""               # nothing to clean
}

@test "create: next_ip is monotonic — destroying a VM doesn't recycle its IP" {
  # Short, distinct base so the letter suffixes can never be truncated away.
  local base; base="m$$"; base="${base:0:8}"
  local a="${base}a" b="${base}b" c="${base}c"
  EXTRA_VMS="$a $b $c"   # set BEFORE first create so teardown cleans on abort
  destroy_quietly "$a"; destroy_quietly "$b"; destroy_quietly "$c"

  vm_cli create "$a"
  vm_cli create "$b"
  local ipb ob
  ipb="$(vm_ip "$b")"; ob="${ipb##*.}"

  destroy_quietly "$a"   # free A's slot
  vm_cli create "$c"
  local ipc oc
  ipc="$(vm_ip "$c")"; oc="${ipc##*.}"

  # C must come after B even though A was freed (allocator never recycles).
  [ "$oc" -gt "$ob" ]

  destroy_quietly "$b"; destroy_quietly "$c"
}

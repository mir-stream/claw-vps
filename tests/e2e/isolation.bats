#!/usr/bin/env bats
# L5 security E2E: live verification of the isolation model with two booted VMs
# plus the host's iptables chains. This is the core security contract:
#   VM ↔ VM            blocked
#   VM → host          blocked (10.42.0.1)
#   VM → internet      allowed (NAT)        — skipped if the host has no internet
#   VM → home LAN      blocked              — skipped unless LAN_TARGET is set
#   firewall rebuild   idempotent (VPS-FWD/VPS-IN stable across reruns)

load ../lib/common.bash

SETUP_NET="/usr/sbin/vps-setup-network"

setup() {
  require_host
  A="bia$$"; B="bib$$"
  A="$(echo "$A" | cut -c1-11)"; B="$(echo "$B" | cut -c1-11)"
  destroy_quietly "$A"; destroy_quietly "$B"
}

teardown() {
  destroy_quietly "$A"; destroy_quietly "$B"
}

@test "isolation: VM A cannot ping VM B" {
  vm_cli create "$A"
  vm_cli create "$B"
  local ipa ipb
  ipa="$(vm_ip "$A")"; ipb="$(vm_ip "$B")"

  wait_for_ssh "$ipa" || { vm_cli logs "$A" 2>/dev/null | tail -40; false; }
  wait_for_ssh "$ipb" || { vm_cli logs "$B" 2>/dev/null | tail -40; false; }

  run guest_ping "$ipa" "$ipb"
  [ "$status" -ne 0 ]
}

@test "isolation: VM A cannot ping the host (10.42.0.1)" {
  vm_cli create "$A"
  local ipa
  ipa="$(vm_ip "$A")"
  wait_for_ssh "$ipa" || { vm_cli logs "$A" 2>/dev/null | tail -40; false; }

  run guest_ping "$ipa" "10.42.0.1"
  [ "$status" -ne 0 ]
}

@test "isolation: VM A can reach the internet (8.8.8.8)" {
  host_has_internet || skip "host has no internet — cannot assert VM egress"
  vm_cli create "$A"
  local ipa
  ipa="$(vm_ip "$A")"
  wait_for_ssh "$ipa" || { vm_cli logs "$A" 2>/dev/null | tail -40; false; }

  run guest_ping "$ipa" "8.8.8.8"
  [ "$status" -eq 0 ]
}

@test "isolation: VM A cannot ping the home LAN (LAN_TARGET)" {
  [ -n "$LAN_TARGET" ] || skip "LAN_TARGET unset — set e.g. LAN_TARGET=192.168.1.1"
  vm_cli create "$A"
  local ipa
  ipa="$(vm_ip "$A")"
  wait_for_ssh "$ipa" || { vm_cli logs "$A" 2>/dev/null | tail -40; false; }

  run guest_ping "$ipa" "$LAN_TARGET"
  [ "$status" -ne 0 ]
}

@test "firewall: vps-setup-network is idempotent (chains stable across reruns)" {
  [ -x "$SETUP_NET" ] || skip "$SETUP_NET not installed"

  sudo "$SETUP_NET" >/dev/null
  run sudo iptables -S VPS-FWD; [ "$status" -eq 0 ]
  run sudo iptables -S VPS-IN;  [ "$status" -eq 0 ]
  local fwd1 in1
  fwd1="$(sudo iptables -S VPS-FWD | wc -l)"
  in1="$(sudo iptables -S VPS-IN | wc -l)"

  sudo "$SETUP_NET" >/dev/null
  local fwd2 in2
  fwd2="$(sudo iptables -S VPS-FWD | wc -l)"
  in2="$(sudo iptables -S VPS-IN | wc -l)"

  [ "$fwd1" -eq "$fwd2" ]
  [ "$in1" -eq "$in2" ]
}

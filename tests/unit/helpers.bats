#!/usr/bin/env bats
# Unit tests for the pure helpers in `clawvps`. No root, no VM — we source the script
# (it self-guards its dispatch) and call the functions directly against a temp
# VMROOT. These run in ~1s on any machine, including in CI.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export VMROOT="$BATS_TEST_TMPDIR/vms"
  mkdir -p "$VMROOT"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/clawvps"
}

@test "ip_to_int: known value" {
  run ip_to_int 10.42.0.1
  [ "$status" -eq 0 ]
  [ "$output" -eq 170524673 ]
}

@test "ip_to_int / int_to_ip: roundtrip" {
  run int_to_ip "$(ip_to_int 10.42.0.10)"
  [ "$output" = "10.42.0.10" ]
  run int_to_ip "$(ip_to_int 10.42.255.254)"
  [ "$output" = "10.42.255.254" ]
}

@test "mac_for_ip: locally-administered MAC derived from IP octets" {
  run mac_for_ip 10.42.0.10
  [ "$output" = "06:00:0a:2a:00:0a" ]
  run mac_for_ip 10.42.1.255
  [ "$output" = "06:00:0a:2a:01:ff" ]
}

@test "next_ip: empty pool returns POOL_FIRST" {
  run next_ip
  [ "$output" = "10.42.0.10" ]
}

@test "next_ip: increments past the highest allocated IP" {
  mkdir -p "$VMROOT/a" "$VMROOT/b"
  echo "10.42.0.10" > "$VMROOT/a/ip"
  echo "10.42.0.15" > "$VMROOT/b/ip"
  run next_ip
  [ "$output" = "10.42.0.16" ]
}

@test "next_ip: ignores VM dirs without an ip file" {
  mkdir -p "$VMROOT/halfbuilt"   # no ip file (e.g. a create that failed early)
  run next_ip
  [ "$output" = "10.42.0.10" ]
}

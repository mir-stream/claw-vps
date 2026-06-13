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

# Tailscale is the access path (subnet router) — without it a VM is unreachable.
# init must abort hard, not warn-and-continue to key registration. We stub out
# need_root and empty the PATH so `command -v tailscale` finds nothing.
@test "cmd_init: aborts when tailscale is missing" {
  need_root() { :; }
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  PATH="$BATS_TEST_TMPDIR/empty" run cmd_init
  [ "$status" -eq 1 ]
  [[ "$output" == *"tailscale not found"* ]]
  [[ "$output" != *"[2/3]"* ]]   # never reached SSH key registration
}

@test "cmd_init: aborts when tailscale is installed but logged out" {
  need_root() { :; }
  # status reports a non-Running backend; set/up are never reached.
  tailscale() { case "$1" in status) echo '"BackendState": "NeedsLogin"';; *) return 0;; esac; }
  run cmd_init <<<""
  [ "$status" -eq 1 ]
  [[ "$output" == *"not logged in"* ]]
  [[ "$output" != *"[2/3]"* ]]   # never reached SSH key registration
}

@test "cmd_init: advertises and confirms an already-approved route" {
  need_root() { :; }
  # Logged in (BackendState Running) with the /16 already in the Self block, so
  # [3/3] short-circuits instead of entering the wait loop.
  tailscale() {
    case "$1" in
      status) printf '%s\n' '"BackendState": "Running"' '"Self": {' '"AllowedIPs": ["10.42.0.0/16"]' '},' '"Peer": {}';;
      *) return 0;;
    esac
  }
  run cmd_init <<<""              # empty stdin → skip the key prompt
  [ "$status" -eq 0 ]
  [[ "$output" == *"route advertised"* ]]
  [[ "$output" == *"[2/3]"* ]]                 # advanced past the tailscale gate
  [[ "$output" == *"already approved and active"* ]]   # [3/3] detected the route
}

@test "_await_route: gives up (returns 1) when the route never approves" {
  _route_active() { return 1; }   # never approved
  run _await_route 0 0            # zero timeout/interval → no sleeping, no hang
  [ "$status" -eq 1 ]
}

@test "_await_route: returns 0 as soon as the route is active" {
  _route_active() { return 0; }   # already approved
  run _await_route 0 0
  [ "$status" -eq 0 ]
}

# ---- clawvps tune pure helpers ---------------------------------------------

@test "auto_mem_high_mib: total minus the 2048 MiB host reserve" {
  run auto_mem_high_mib 16384
  [ "$status" -eq 0 ]
  [ "$output" -eq 14336 ]   # 16384 - 2048
}

@test "auto_mem_high_mib: fails (no output) when result is below the floor" {
  run auto_mem_high_mib 2048   # 2048 - 2048 = 0, under TUNE_MIN_MEM_HIGH_MIB
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  run auto_mem_high_mib 2200   # 152 MiB, still below the 512 floor
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "auto_swap_mib: equals total RAM below the cap" {
  run auto_swap_mib 8192
  [ "$output" -eq 8192 ]
}

@test "auto_swap_mib: caps at 16384 MiB on big-RAM hosts" {
  run auto_swap_mib 65536
  [ "$output" -eq 16384 ]
  run auto_swap_mib 16384   # exactly at the cap stays put
  [ "$output" -eq 16384 ]
}

@test "normalize_size_mib: bare integer is treated as MiB" {
  run normalize_size_mib 8000
  [ "$output" -eq 8000 ]
}

@test "normalize_size_mib: G/M/K/T suffixes (binary, MiB-rounded)" {
  run normalize_size_mib 12G
  [ "$output" -eq 12288 ]
  run normalize_size_mib 8000M
  [ "$output" -eq 8000 ]
  run normalize_size_mib 2048K
  [ "$output" -eq 2 ]
  run normalize_size_mib 1T
  [ "$output" -eq 1048576 ]
}

@test "normalize_size_mib: rejects garbage" {
  run normalize_size_mib 12X
  [ "$status" -eq 1 ]
  run normalize_size_mib abc
  [ "$status" -eq 1 ]
  run normalize_size_mib ""
  [ "$status" -ne 0 ]
}

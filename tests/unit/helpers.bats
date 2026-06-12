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

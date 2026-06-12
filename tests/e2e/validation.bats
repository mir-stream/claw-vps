#!/usr/bin/env bats
# Fast E2E checks: argument validation rejects bad input before touching disk or
# booting anything. Needs sudo (cmd_create gates on root first), but no base image.

load ../lib/common.bash

setup() {
  command -v firecracker >/dev/null 2>&1 || skip "firecracker not installed — E2E needs a configured host"
  sudo -n true 2>/dev/null || skip "passwordless sudo required for E2E"
}

@test "create: rejects a name with illegal characters" {
  run vm_cli create "bad_name!"
  [ "$status" -ne 0 ]
  [[ "$output" == *"name must be lowercase"* ]]
}

@test "create: rejects a name longer than the tap-device limit" {
  run vm_cli create "waytoolongname"
  [ "$status" -ne 0 ]
  [[ "$output" == *"max 11 chars"* ]]
}

@test "create: rejects non-numeric --cpus" {
  run vm_cli create okname --cpus two
  [ "$status" -ne 0 ]
  [[ "$output" == *"--cpus must be a number"* ]]
}

@test "create: rejects non-numeric --mem" {
  run vm_cli create okname --mem lots
  [ "$status" -ne 0 ]
  [[ "$output" == *"--mem must be a number"* ]]
}

@test "create: rejects an unknown option" {
  run vm_cli create okname --bogus 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "build: rejects foundation targets (moved to setup)" {
  run vm_cli build kernel
  [ "$status" -ne 0 ]
  [[ "$output" == *"vm setup kernel"* ]]
}

@test "destroy: rejects a non-existent VM" {
  run vm_cli destroy doesnotexist --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such VM"* ]]
}

@test "start/stop/restart/status: reject a non-existent VM" {
  for sub in start stop restart status; do
    run vm_cli "$sub" doesnotexist
    [ "$status" -ne 0 ]
    [[ "$output" == *"no such VM"* ]]
  done
}

@test "create: a mutating command without root prints 'run with sudo'" {
  # Run the script directly (NOT via vm_cli, which uses sudo) as the current
  # unprivileged user. need_root must reject before touching anything.
  [ "$(id -u)" -ne 0 ] || skip "test must run as a non-root user"
  run env -i PATH="$PATH" "$VM_BIN" create x
  [ "$status" -ne 0 ]
  [[ "$output" == *"run with sudo"* ]]
}

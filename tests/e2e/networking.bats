#!/usr/bin/env bats
# Networking E2E: IP-pool allocation — a second VM gets the next sequential IP
# from the 10.42.0.0 pool. Boots two VMs. (L2 isolation is covered in
# isolation.bats.)

load ../lib/common.bash

setup() {
  require_host
  A="bna$$"; B="bnb$$"
  A="$(echo "$A" | cut -c1-11)"; B="$(echo "$B" | cut -c1-11)"
  destroy_quietly "$A"; destroy_quietly "$B"
}

teardown() {
  destroy_quietly "$A"; destroy_quietly "$B"
}

@test "ip allocation: a second VM gets the next sequential IP" {
  vm_cli create "$A"
  vm_cli create "$B"

  ipa="$(vm_ip "$A")"; ipb="$(vm_ip "$B")"
  [[ "$ipa" == 10.42.0.* ]]
  [[ "$ipb" == 10.42.0.* ]]

  # B was created after A, so its host octet is strictly higher.
  oa="${ipa##*.}"; ob="${ipb##*.}"
  [ "$ob" -gt "$oa" ]
}

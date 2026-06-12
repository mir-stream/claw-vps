#!/usr/bin/env bash
# Test runner for claw-vps. Three layers:
#   lint  — shellcheck on every shell script (fast, no root)
#   unit  — bats: pure helpers in `clawvps` (fast, no root, no VM)
#   e2e   — bats: real create/boot/ssh/destroy on the host VM (slow, needs root)
#
# Usage:
#   tests/run-tests.sh           # lint + unit  (safe anywhere)
#   tests/run-tests.sh lint
#   tests/run-tests.sh unit
#   tests/run-tests.sh e2e       # run this ON the host VM
#   tests/run-tests.sh all       # lint + unit + e2e
set -euo pipefail
cd "$(dirname "$0")/.."

SHELL_FILES=(clawvps build-base.sh build-kernel.sh setup-network.sh packaging/make-deb.sh)

run_lint() {
  command -v shellcheck >/dev/null 2>&1 || {
    echo "SKIP lint: shellcheck not installed (apt install shellcheck / brew install shellcheck)"; return 0; }
  echo "== shellcheck =="
  shellcheck "${SHELL_FILES[@]}"
  echo "  OK"
}

run_unit() {
  command -v bats >/dev/null 2>&1 || {
    echo "SKIP unit: bats not installed (apt install bats / brew install bats-core)"; return 0; }
  echo "== unit =="
  bats tests/unit
}

run_e2e() {
  command -v bats >/dev/null 2>&1 || { echo "SKIP e2e: bats not installed"; return 0; }
  echo "== e2e (host VM) =="
  bats tests/e2e
}

# Opt-in: foundation builds (clawvps setup base/kernel) are very slow and network-heavy,
# so the normal e2e suite assumes they already exist. This target is a placeholder
# for wiring those live builds in later; for now it just runs the regular e2e.
run_e2e_full() {
  echo "== e2e-full =="
  echo "(foundation builds 'clawvps setup base/kernel' not yet wired — running standard e2e)"
  run_e2e
}

case "${1:-default}" in
  lint)     run_lint ;;
  unit)     run_unit ;;
  e2e)      run_e2e ;;
  e2e-full) run_e2e_full ;;
  all)      run_lint; run_unit; run_e2e ;;
  default)  run_lint; run_unit
            echo "(e2e skipped — run 'tests/run-tests.sh e2e' on the host VM)" ;;
  *) echo "usage: $0 {lint|unit|e2e|e2e-full|all}" >&2; exit 1 ;;
esac

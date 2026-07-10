#!/usr/bin/env bats
# Tests for run_once_before_10-install-prereqs.sh — specifically detect_node_major(),
# whose missing-node path must NOT abort the whole bootstrap under set -euo pipefail.
# Regression guard: a nodeless box used to bail out here (node -v -> 127) before Oh My
# Zsh and the dotfiles were ever written.
load test_helper

PREREQS="$REPO_ROOT/run_once_before_10-install-prereqs.sh"

setup() { setup_stub_path; }

# Extract just the detect_node_major() function into a sourceable file (mirrors the
# awk-extraction idiom the agent.hcl branch tests use for non-sourceable content).
_extract_detect() {
  awk '/^detect_node_major\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$PREREQS" \
    > "$BATS_TEST_TMPDIR/fn.sh"
  [ -s "$BATS_TEST_TMPDIR/fn.sh" ]
}

@test "detect_node_major: empty output and clean exit when node is absent" {
  _extract_detect
  # PATH restricted to the (node-free) stub dir; run under the script's strict mode
  # to prove a missing node cannot abort via set -e / pipefail. printf/echo are
  # builtins, so no external tools are needed on this path.
  run bash -c 'set -euo pipefail; PATH="'"$STUB_BIN"'"; . "'"$BATS_TEST_TMPDIR"'/fn.sh"; out="$(detect_node_major)"; printf "rc=%s out=[%s]" "$?" "$out"'
  [ "$status" -eq 0 ]
  [ "$output" = "rc=0 out=[]" ]
}

@test "detect_node_major: prints the major version when node is present (>=22)" {
  _extract_detect
  make_stub node 'echo v22.3.1'
  run bash -c 'set -euo pipefail; . "'"$BATS_TEST_TMPDIR"'/fn.sh"; detect_node_major'
  [ "$status" -eq 0 ]
  [ "$output" = "22" ]
}

@test "detect_node_major: reports an older major so the installer can upgrade it" {
  _extract_detect
  make_stub node 'echo v18.19.0'
  run bash -c 'set -euo pipefail; . "'"$BATS_TEST_TMPDIR"'/fn.sh"; detect_node_major'
  [ "$status" -eq 0 ]
  [ "$output" = "18" ]
}

@test "install-prereqs script passes bash -n" {
  run bash -n "$PREREQS"
  [ "$status" -eq 0 ]
}

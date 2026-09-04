#!/usr/bin/env bash
# Tests for .chezmoiscripts/run_after_53-npx-cache-prune.sh — the npx cache
# pruner. Validates shell syntax and the actual prune behavior against a
# fabricated cache: a dangling .bin shim must get its whole entry removed,
# a healthy entry must survive, and a missing cache must be a no-op.
load test_helper

SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_53-npx-cache-prune.sh"

@test "script parses as valid bash" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# Stub `npm` on PATH so the script's presence probe passes regardless of
# what the test host has installed.
_setup_npm_stub() {
  setup_stub_path
  make_stub npm 'exit 0'
}

@test "prunes entries with dangling bin shims, keeps healthy ones" {
  _setup_npm_stub
  local cache="$BATS_TEST_TMPDIR/home/.npm/_npx"
  mkdir -p "$cache/badentry/node_modules/.bin" "$cache/goodentry/node_modules/.bin" "$cache/goodentry/node_modules/pkg/bin"

  ln -s ../pkg/bin/missing.js "$cache/badentry/node_modules/.bin/some-mcp"
  printf '#!/bin/sh\n' > "$cache/goodentry/node_modules/pkg/bin/real.js"
  chmod +x "$cache/goodentry/node_modules/pkg/bin/real.js"
  ln -s ../pkg/bin/real.js "$cache/goodentry/node_modules/.bin/real-mcp"

  HOME="$BATS_TEST_TMPDIR/home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -d "$cache/badentry" ]
  [ -d "$cache/goodentry" ]
}

@test "missing cache directory is a no-op" {
  _setup_npm_stub
  HOME="$BATS_TEST_TMPDIR/home" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

# Common BATS helpers.
export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# Prepend a sandbox bin dir to PATH so we can stub executables (vault, launchctl…).
setup_stub_path() {
  export STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  export PATH="$STUB_BIN:$PATH"
}

# make_stub NAME 'bash body'  — write an executable stub onto the sandbox PATH.
make_stub() {
  local name="$1" body="$2"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$STUB_BIN/$name"
  chmod +x "$STUB_BIN/$name"
}

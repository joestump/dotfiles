#!/usr/bin/env bats
# Tests for run_after_34-install-go-clis (cairn + switchboard built from their
# managed clones, the harness model) and the credential-guarded externals that
# feed it. Both repos are PRIVATE on Gitea and both module paths point at a
# GitHub location that does not exist, so two things must stay true: the clones
# must sit behind the credential guard (an unauthenticated git-repo external
# aborts the whole apply), and neither tool may drift into go-tools.txt, where
# `go install <module>@latest` can never resolve.
load test_helper

SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_34-install-go-clis.sh.tmpl"
EXTERNAL="$REPO_ROOT/.chezmoiexternal.toml"
DATA="$REPO_ROOT/.chezmoidata.yaml"
GO_TOOLS="$REPO_ROOT/dot_config/dotfiles/go-tools.txt"

_render_script() {
  chezmoi execute-template --source "$REPO_ROOT" < "$SCRIPT"
}

# Render .chezmoiexternal.toml under a controlled $HOME.
_render_external() {
  HOME="$1" chezmoi execute-template --source "$REPO_ROOT" < "$EXTERNAL"
}

@test "go-clis: the data file declares both clone urls on the private Gitea org" {
  grep -qE '^cairnRepo: "https://gitea\.stump\.rocks/stump\.wtf/cairn\.git"$' "$DATA"
  grep -qE '^switchboardRepo: "https://gitea\.stump\.rocks/stump\.wtf/switchboard\.git"$' "$DATA"
}

@test "go-clis: neither CLI is a go-tools.txt entry (their module paths cannot be go-installed)" {
  ! grep -qE 'joestump/(cairn|switchboard)' "$GO_TOOLS"
}

@test "go-clis: build script sources ui-lib and builds both cmd packages" {
  grep -q 'ui-lib.sh' "$SCRIPT"
  grep -q '^build_cli cairn ' "$SCRIPT"
  grep -q '^build_cli switchboard ' "$SCRIPT"
  grep -q './cmd/cairn' "$SCRIPT"
  grep -q './cmd/switchboard' "$SCRIPT"
}

@test "go-clis: switchboard gets its main.version ldflag, mirroring its Makefile" {
  grep -q -- '-X main.version=@VERSION@' "$SCRIPT"
}

@test "go-clis: a failed build surfaces (non-zero exit) instead of a silent warn" {
  # The whole point of the scheduled run is that a failure means something; the
  # harness script's history explains why a warn-only build was a bug.
  grep -q 'failed=1' "$SCRIPT"
  grep -q 'exit 1' "$SCRIPT"
}

@test "go-clis: rendered script is valid bash with both clone urls substituted" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'https://gitea.stump.rocks/stump.wtf/cairn.git'* ]]
  [[ "$output" == *'https://gitea.stump.rocks/stump.wtf/switchboard.git'* ]]
  [[ "$output" != *'{{'* ]]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/script.sh"
  bash -n "$BATS_TEST_TMPDIR/script.sh"
}

@test "go-clis: rendered script exports GOPRIVATE for the private forge" {
  # A chezmoi run script gets almost none of the login-shell environment, so the
  # GOPRIVATE export in go.zsh.tmpl never reaches it (the harness trap).
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render_script
  [ "$status" -eq 0 ]
  [[ "$output" == *'export GOPRIVATE="gitea.stump.rocks/*'* ]]
}

@test "go-clis: rendered script is a no-op when the go toolchain is absent" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render_script
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/script.sh"
  local fh="$BATS_TEST_TMPDIR/home"; mkdir -p "$fh"
  setup_stub_path
  # A PATH with no `go` on it (the sandbox bin plus the POSIX basics only).
  run env HOME="$fh" PATH="$STUB_BIN:/usr/bin:/bin" bash "$BATS_TEST_TMPDIR/script.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"go toolchain absent"* ]]
}

@test "go-clis: rendered script skips each tool whose clone is absent, and still exits 0" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render_script
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/script.sh"
  local fh="$BATS_TEST_TMPDIR/home"; mkdir -p "$fh"
  setup_stub_path
  make_stub go 'echo "go should not be invoked without a clone" >&2; exit 1'
  run env HOME="$fh" PATH="$STUB_BIN:/usr/bin:/bin" bash "$BATS_TEST_TMPDIR/script.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cairn source not cloned yet"* ]]
  [[ "$output" == *"switchboard source not cloned yet"* ]]
}

@test "go-clis: a credential-less node OMITS both private externals" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local fh="$BATS_TEST_TMPDIR/nocreds"; mkdir -p "$fh"
  run _render_external "$fh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"cairn-src"* ]]
  [[ "$output" != *"switchboard-src"* ]]
}

@test "go-clis: a provisioned node INCLUDES both externals as ff-only quiet git-repo pulls" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local fh="$BATS_TEST_TMPDIR/creds"; mkdir -p "$fh"; : > "$fh/.git-credentials"
  run _render_external "$fh"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/external.toml"
  python3 - "$BATS_TEST_TMPDIR/external.toml" <<'PY'
import sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
for k, url in ((".local/share/cairn-src", "https://gitea.stump.rocks/stump.wtf/cairn.git"),
               (".local/share/switchboard-src", "https://gitea.stump.rocks/stump.wtf/switchboard.git")):
    assert d[k]["type"] == "git-repo", k
    assert d[k]["url"] == url, (k, d[k]["url"])
    assert d[k]["pull"]["args"] == ["--ff-only", "--quiet"], k
PY
}

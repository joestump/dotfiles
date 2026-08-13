#!/usr/bin/env bats
# Regression guard for private_dot_ssh/private_config.tmpl — the ssh config is
# generated from the `ssh:` block in .chezmoidata.yaml, so these tests render the
# template first and then assert against the OUTPUT (that is what ssh actually
# reads). A second group renders the template against synthetic data to prove the
# shaping is genuinely data-driven rather than hardcoded.
load test_helper

SSH_TMPL="$REPO_ROOT/private_dot_ssh/private_config.tmpl"

# Render the real template (real .chezmoidata.yaml) into $BATS_TEST_TMPDIR/config
# and echo the path. Skips the test when chezmoi isn't installed.
_render() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local out="$BATS_TEST_TMPDIR/config"
  chezmoi execute-template --source "$REPO_ROOT" < "$SSH_TMPL" > "$out"
  echo "$out"
}

# ────── source layout ──────

@test "ssh-config: source is a template under a private_ dir (mode 0600 after apply)" {
  [ -f "$SSH_TMPL" ]
  # The private_ prefix on the DIRECTORY is what tells chezmoi to apply ~/.ssh
  # with restrictive permissions; the file itself is private_config.tmpl.
  basename "$(dirname "$SSH_TMPL")" | grep -q '^private_'
  basename "$SSH_TMPL" | grep -q '^private_config\.tmpl$'
}

@test "ssh-config: no static private_config left behind (would shadow the template)" {
  # chezmoi would treat both as targets for ~/.ssh/config; the stale one wins
  # nondeterministically. Exactly one source file may exist.
  [ ! -e "$REPO_ROOT/private_dot_ssh/private_config" ]
}

@test "ssh-config: the template hardcodes no host data" {
  # Every hostname/user/IP must come from .chezmoidata.yaml, not the template.
  run grep -Eic 'stump\.rocks|192\.168\.|joestump|id_ansible' "$SSH_TMPL"
  [ "$output" -eq 0 ]
}

# ────── rendered output: the directives that matter ──────

@test "ssh-config: renders and ssh parses the result" {
  local cfg; cfg="$(_render)" || return $?
  command -v ssh >/dev/null 2>&1 || skip "ssh not installed"
  run ssh -F "$cfg" -G github.com
  [ "$status" -eq 0 ]
}

@test "ssh-config: github block uses port 443 and ssh.github.com" {
  local cfg; cfg="$(_render)" || return $?
  grep -Eq '^Host .*github\.com' "$cfg"
  grep -Eq '^\s*Hostname\s+ssh\.github\.com' "$cfg"
  grep -Eq '^\s*Port\s+443' "$cfg"
}

# The claude-* RemoteCommand quoting guard lived here until 79e39ab dropped the
# dead claude-* shortcut from the ssh config. There is no RemoteCommand left to
# assert on; restore the test alongside any block that reintroduces one.

@test "ssh-config: ControlMaster block is present with %C ControlPath" {
  local cfg; cfg="$(_render)" || return $?
  grep -Eq 'ControlMaster\s+auto' "$cfg"
  grep -Eq 'ControlPath\s+.*%C' "$cfg"
  grep -Eq 'ControlPersist\s+10m' "$cfg"
}

@test "ssh-config: ControlMaster rule excludes github.com" {
  local cfg; cfg="$(_render)" || return $?
  local host_block
  host_block=$(grep -B5 'ControlMaster' "$cfg" | grep '^Host ')
  [[ "$host_block" != *github.com* ]]
}

@test "ssh-config: infra ProxyJump hosts use id_ansible IdentityFile" {
  local cfg; cfg="$(_render)" || return $?
  local count
  count=$(grep -c 'IdentityFile ~/.ssh/id_ansible' "$cfg")
  [ "$count" -ge 3 ]
}

@test "ssh-config: every jump host carries the full shared option set" {
  local cfg; cfg="$(_render)" || return $?
  # One Host block per address in ssh.jump.hosts, each with every shared option.
  # Asserted per block, not with a file-global count: other blocks legitimately
  # share individual options (github.com also pins StrictHostKeyChecking
  # accept-new), so a global grep -c overcounts.
  local n bad
  n=$(grep -c 'ProxyJump root@dagda.stump.rocks' "$cfg")
  [ "$n" -ge 3 ]
  bad=$(awk '
    function flush() { if (jump && !(io && shk && idf)) bad++; jump=io=shk=idf=0 }
    /^Host /                                  { flush() }
    /ProxyJump root@dagda\.stump\.rocks/      { jump=1 }
    /IdentitiesOnly yes/                      { io=1 }
    /StrictHostKeyChecking accept-new/        { shk=1 }
    /IdentityFile ~\/\.ssh\/id_ansible/       { idf=1 }
    END { flush(); print bad+0 }
  ' "$cfg")
  [ "$bad" -eq 0 ]
}

@test "ssh-config: specific blocks render BEFORE the multiplex catch-all" {
  local cfg; cfg="$(_render)" || return $?
  # ssh_config is first-match-wins per keyword, so the wildcard rule must be last
  # or it would capture keywords intended for the specific blocks.
  local first_specific last_host
  first_specific=$(grep -n '^Host ' "$cfg" | head -1 | cut -d: -f1)
  last_host=$(grep -n '^Host ' "$cfg" | tail -1 | cut -d: -f1)
  [ "$first_specific" -lt "$last_host" ]
  # The final Host line is the multiplexing wildcard.
  sed -n "${last_host}p" "$cfg" | grep -q '\*'
}

@test "ssh-config: every Host block that sets HostName also sets User" {
  local cfg; cfg="$(_render)" || return $?
  awk '
    /^Host /                { host=$0; has_hostname=0; has_user=0 }
    /Hostname|HostName/     { has_hostname=1 }
    /^[ \t]*User[ \t]/      { has_user=1 }
    /^$/ {
      if (has_hostname && !has_user)
        print "MISSING USER: " host
      host=""; has_hostname=0; has_user=0
    }
    END {
      if (has_hostname && !has_user)
        print "MISSING USER: " host
    }
  ' "$cfg" > "$BATS_TEST_TMPDIR/missing"
  run cat "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ────── rendered output: ssh's own resolution ──────

@test "ssh-config: ssh -G resolves ControlMaster for an infra host" {
  local cfg; cfg="$(_render)" || return $?
  command -v ssh >/dev/null 2>&1 || skip "ssh not installed"
  run ssh -F "$cfg" -G lir
  [ "$status" -eq 0 ]
  [[ "$output" == *"controlmaster auto"* ]]
  [[ "$output" == *"controlpath"* ]]
  [[ "$output" == *"controlpersist 600"* ]]
}

@test "ssh-config: ssh -G does NOT set ControlMaster for github.com" {
  local cfg; cfg="$(_render)" || return $?
  command -v ssh >/dev/null 2>&1 || skip "ssh not installed"
  run ssh -F "$cfg" -G github.com
  [ "$status" -eq 0 ]
  [[ "$output" != *"controlmaster auto"* ]]
}

@test "ssh-config: the bare cloud01 alias resolves to the bootstrap IP" {
  local cfg; cfg="$(_render)" || return $?
  command -v ssh >/dev/null 2>&1 || skip "ssh not installed"
  # cloud01.stump.rocks is NXDOMAIN on the LAN, so the short alias must map to
  # the literal IP rather than falling through to a DNS lookup for "cloud01".
  run ssh -F "$cfg" -G cloud01
  [ "$status" -eq 0 ]
  [[ "$output" == *"hostname 179.237.64.122"* ]]
}

# ────── the shaping is data-driven, not hardcoded ──────

# Render the template against synthetic ssh data in a throwaway source dir. This
# is what proves the block shaping actually comes from .chezmoidata.yaml.
_render_with_data() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local src="$BATS_TEST_TMPDIR/src"
  mkdir -p "$src"
  cp "$SSH_TMPL" "$src/private_config.tmpl"
  cat > "$src/.chezmoidata.yaml"
  chezmoi execute-template --source "$src" < "$src/private_config.tmpl"
}

@test "ssh-config: a host added to data produces a Host block" {
  run _render_with_data <<'YAML'
ssh:
  hosts:
    - patterns: ["newbox", "newbox.example.net"]
      options:
        HostName: "10.0.0.9"
        User: "someone"
  jump:
    options: {}
    hosts: []
  multiplex:
    patterns: ["*.example.net"]
    options:
      ControlMaster: "auto"
YAML
  [ "$status" -eq 0 ]
  [[ "$output" == *"Host newbox newbox.example.net"* ]]
  [[ "$output" == *"HostName 10.0.0.9"* ]]
  [[ "$output" == *"User someone"* ]]
}

@test "ssh-config: a list-valued option emits the keyword once per element" {
  run _render_with_data <<'YAML'
ssh:
  hosts:
    - patterns: ["multi"]
      options:
        IdentityFile:
          - "~/.ssh/id_one"
          - "~/.ssh/id_two"
  jump:
    options: {}
    hosts: []
  multiplex:
    patterns: ["*.nowhere"]
    options:
      ControlMaster: "auto"
YAML
  [ "$status" -eq 0 ]
  [ "$(grep -c 'IdentityFile ~/.ssh/id_one' <<<"$output")" -eq 1 ]
  [ "$(grep -c 'IdentityFile ~/.ssh/id_two' <<<"$output")" -eq 1 ]
}

@test "ssh-config: each jump host expands into its own block with shared options" {
  run _render_with_data <<'YAML'
ssh:
  hosts: []
  jump:
    options:
      User: "jumpuser"
      ProxyJump: "root@bastion.example"
    hosts:
      - "10.1.1.1"
      - "10.1.1.2"
      - "10.1.1.3"
  multiplex:
    patterns: ["*.nowhere"]
    options:
      ControlMaster: "auto"
YAML
  [ "$status" -eq 0 ]
  [ "$(grep -c '^Host 10\.1\.1\.' <<<"$output")" -eq 3 ]
  [ "$(grep -c 'ProxyJump root@bastion.example' <<<"$output")" -eq 3 ]
  [ "$(grep -c 'User jumpuser' <<<"$output")" -eq 3 ]
}

@test "ssh-config: a missing group is omitted, not an apply-aborting error" {
  # chezmoi renders with missingkey=error, and a template error aborts the WHOLE
  # apply — not just this file. A machine whose [data.ssh] override drops a group
  # must degrade to "skip that group" instead of taking the apply down with it.
  run _render_with_data <<'YAML'
ssh:
  hosts:
    - patterns: ["only"]
      options:
        User: "u"
YAML
  [ "$status" -eq 0 ]
  [[ "$output" == *"Host only"* ]]
  [[ "$output" != *"ProxyJump"* ]]
  [[ "$output" != *"ControlMaster"* ]]
}

@test "ssh-config: an empty ssh block renders headers only, no error" {
  run _render_with_data <<'YAML'
ssh: {}
YAML
  [ "$status" -eq 0 ]
  [ "$(grep -c '^Host ' <<<"$output")" -eq 0 ]
}

@test "ssh-config: a block with no options still renders its Host line" {
  run _render_with_data <<'YAML'
ssh:
  hosts:
    - patterns: ["bare"]
YAML
  [ "$status" -eq 0 ]
  [[ "$output" == *"Host bare"* ]]
}

# ────── per-machine [data.ssh] overrides ──────

# Render the REAL template + real data, but under a chezmoi.toml whose
# [data.ssh] table overrides part of it. Documented in maintenance.md.
#
# --config is passed EXPLICITLY rather than relying on the $HOME override alone.
# chezmoi resolves its config dir through os.UserConfigDir(), which honours
# $XDG_CONFIG_HOME ahead of $HOME/.config on Linux — so on a box that exports it,
# overriding HOME still left the render reading the MACHINE's real chezmoi.toml.
# A host carrying its own [data.ssh] overrides then failed these tests while CI
# and macOS passed, which inverts the point of `make test` as the pre-push gate.
# See #138.
_render_with_override() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local fh="$BATS_TEST_TMPDIR/home"
  mkdir -p "$fh/.config/chezmoi"
  cat > "$fh/.config/chezmoi/chezmoi.toml"
  HOME="$fh" chezmoi execute-template \
    --config "$fh/.config/chezmoi/chezmoi.toml" \
    --source "$REPO_ROOT" < "$SSH_TMPL"
}

@test "ssh-config: an options override DEEP-MERGES (siblings survive)" {
  run _render_with_override <<'TOML'
[data.ssh.jump.options]
  ProxyJump = "root@other.bastion"
TOML
  [ "$status" -eq 0 ]
  # The overridden key changes...
  [[ "$output" == *"ProxyJump root@other.bastion"* ]]
  [[ "$output" != *"ProxyJump root@dagda.stump.rocks"* ]]
  # ...and its siblings from .chezmoidata.yaml are retained.
  [[ "$output" == *"IdentityFile ~/.ssh/id_ansible"* ]]
  [[ "$output" == *"StrictHostKeyChecking accept-new"* ]]
  [[ "$output" == *"IdentitiesOnly yes"* ]]
}

@test "ssh-config: a host-list override REPLACES rather than appends" {
  run _render_with_override <<'TOML'
[data.ssh.jump]
  hosts = ["10.9.9.9"]
TOML
  [ "$status" -eq 0 ]
  [[ "$output" == *"Host 10.9.9.9"* ]]
  # The shared defaults still apply to the replacement host...
  [[ "$output" == *"ProxyJump root@dagda.stump.rocks"* ]]
  # ...but the original addresses are gone, not merged in.
  [[ "$output" != *"Host 192.168.100.213"* ]]
}

@test "ssh-config: empty host lists render a valid (multiplex-only) config" {
  run _render_with_data <<'YAML'
ssh:
  hosts: []
  jump:
    options: {}
    hosts: []
  multiplex:
    patterns: ["*.example.org"]
    options:
      ControlMaster: "auto"
      ControlPersist: "10m"
YAML
  [ "$status" -eq 0 ]
  [ "$(grep -c '^Host ' <<<"$output")" -eq 1 ]
  [[ "$output" == *"Host *.example.org"* ]]
}

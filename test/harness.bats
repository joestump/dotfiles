#!/usr/bin/env bats
# Tests for the harness seed (dot_config/harness/*, dot_local/share/crush-signal/*).
#
# Two harnesses ship in the seed: crush-signal (crush driven from Signal, model-pinned)
# and claude-code (Claude Code driven from the Claude app via Remote Control). The
# files have to agree with each other and with dot_config/crush/crush.json.tmpl or the
# harness silently runs the wrong model, or with no Signal channel. These assertions
# pin the couplings that a careless edit to any one file would break.
load test_helper

HARNESS_TOML="$REPO_ROOT/dot_config/harness/harness.toml.tmpl"
HARNESS_ENV="$REPO_ROOT/dot_config/harness/crush-signal.env.tmpl"
# private_ (0600) matches the mode crush itself writes the file with. Without it
# chezmoi wants to chmod 644 on every apply, and because crush has also rewritten
# the contents it stops to ask "…has changed since chezmoi last wrote it?" —
# which wedges any non-interactive apply. Attribute order is create_ then private_.
MODEL_PIN="$REPO_ROOT/dot_local/share/crush-signal/private_crush.json.tmpl"
CRUSH_JSON="$REPO_ROOT/dot_config/crush/crush.json.tmpl"

_render() {
  chezmoi execute-template --source "$REPO_ROOT" < "$1"
}

@test "harness: harness.toml is MANAGED (not create_) so edits reach every machine" {
  # This was create_ — seed-once — on the reasoning that harness's new-harness
  # TUI form rewrites it. That held, but the cost was worse: a create_ file is
  # never updated again, so every edit to the template reached NEW machines only.
  # tars sat on a 2026-07-26 copy whose harness names and profiles had drifted
  # completely from this template, and no amount of czu could reconcile it.
  #
  # The declared set has to win, because it is the only copy that propagates.
  # The TUI-rewrite problem is handled the way this repo handles every other
  # app-fought file: czu_reassert_targets in executable_czu-run.zsh. Deliberate
  # consequence: a harness created through the TUI does not survive a czu.
  [ -f "$HARNESS_TOML" ]
  case "$HARNESS_TOML" in
    */create_*) fail "harness.toml must NOT be create_ — it has to update on czu" ;;
  esac
}

@test "harness: czu reasserts harness.toml, since the TUI rewrites it" {
  # Managed-but-app-rewritten trips chezmoi's changed-since-last-write guard:
  # interactive apply prompts, scheduled apply silently skips. Without this the
  # switch away from create_ would trade one silent no-op for another.
  grep -q '"\$HOME/.config/harness/harness.toml"' \
    "$REPO_ROOT/dot_config/dotfiles/executable_czu-run.zsh"
}

@test "harness: the crush model pin is NOT create_ (the drift guard)" {
  # This was create_ until 2026-08-28, on the reasoning that crush rewrites it
  # on every model change so it is per-machine state rather than declared
  # config. That reasoning cost real money. Crush's TUI model picker rewrote
  # the TARGET mid-session, and create_ means "write only if absent" — so
  # chezmoi never had an opinion about it again. The pin said zai/glm-5.2 while
  # the always-on Signal agent actually ran hyper/kimi-k3 ($3.27/M in,
  # $16.33/M out, max reasoning effort) against a metered account, for six days,
  # while `harness list` still displayed "GLM-5.2 (Z.ai)".
  #
  # The model an unattended agent runs is declared config. Same conclusion
  # harness.toml reached above, for the same reason, and handled the same way:
  # czu_reassert_targets absorbs the TUI rewrite (see the test below).
  #
  # Deliberate consequence: a model picked in the Crush TUI lasts until the
  # next czu. A permanent change is an edit to the template.
  [ -f "$MODEL_PIN" ]
  case "$MODEL_PIN" in
    */create_*) fail "crush model pin must NOT be create_ — that is how it drifted to kimi-k3" ;;
  esac
  [ ! -f "$REPO_ROOT/dot_local/share/crush-signal/create_private_crush.json.tmpl" ]
}

@test "harness: czu reasserts the crush model pin, since the TUI rewrites it" {
  # Managed-but-app-rewritten trips chezmoi's changed-since-last-write guard:
  # interactive apply prompts, scheduled apply silently skips. Without this the
  # switch away from create_ would trade one silent no-op for another — and on
  # the agent box, which runs unattended, it would be the silent one.
  grep -q '"\$HOME/.local/share/crush-signal/crush.json"' \
    "$REPO_ROOT/dot_config/dotfiles/executable_czu-run.zsh"
}

@test "harness: the crush model pin is private_ (0600) so apply never prompts" {
  # crush writes this file 0600. If the source is 0644 chezmoi has a pending chmod
  # forever, and since crush also edits the contents, apply blocks on a y/n prompt
  # with no TTY under launchd/systemd. Guard both the name and the committed mode.
  # The mode comes from the filename attribute, not the file's own bits — git
  # only records the exec bit, so 0600 can never be carried by the blob.
  case "$MODEL_PIN" in
    */private_crush.json.tmpl) ;;
    *) fail "model pin must be private_ (0600), got: $MODEL_PIN" ;;
  esac
}

@test "harness: rendered harness.toml + drop-ins are valid TOML with all seeded harnesses" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # Render as an AGENT login - the scheduled drop-ins are identity-gated, and
  # CI runs as root, where the plain render has none of it. The main config
  # declares the interactive harnesses plus [server].harness_d; the scheduled
  # one-shots live one file each in harness.d/*.toml (stump.wtf/harness PR
  # #227), so the seeded set is the UNION of the main doc and the drop-ins.
  # mktemp --suffix is GNU-only; BSD/macOS mktemp rejects it. chezmoi infers
  # the config format from the extension, so mint the .toml inside a temp dir.
  _cfgdir="$(mktemp -d)"; _cfgdir2="$(mktemp -d)"; _cfg="$_cfgdir2/chezmoi.toml"
  printf '[data]
    agentIdentity = "ci-agent"
' >"$_cfg"
  _render_all() {
    chezmoi execute-template --config "$_cfg" --source "$REPO_ROOT"       < "$HARNESS_TOML" > "$_cfgdir/00-main.toml"
    for _f in "$REPO_ROOT"/dot_config/harness/harness.d/*.toml.tmpl; do
      _n="$(basename "$_f" .toml.tmpl)"
      chezmoi execute-template --config "$_cfg" --source "$REPO_ROOT"         < "$_f" > "$_cfgdir/$_n.toml" || return 1
    done
  }
  run _render_all
  [ "$status" -eq 0 ]
  run bash -c "python3 - '$_cfgdir' <<'PY'
import glob, os, sys, tomllib
cfgdir = sys.argv[1]
docs = {os.path.basename(p): tomllib.load(open(p, 'rb')) for p in sorted(glob.glob(cfgdir + '/*.toml'))}
d = docs.pop('00-main.toml')
names = set(d['harness'])
for fname, dd in docs.items():
    # A drop-in may carry ONLY harness tables - [server]/[profile.*]/[daemon]
    # in one is a config-load error upstream, so catch it here.
    assert set(dd) == {'harness'}, (fname, 'drop-in carries a non-harness table', set(dd))
    over = set(dd['harness']) & names
    assert not over, (fname, 'duplicate harness across config+drop-ins', over)
    names |= set(dd['harness'])
assert names == {'crush-signal', 'claude-code', 'claude-headless',
                 'stumpcloud-sweep', 'pr-sweep', 'issue-sweep',
                 'blog-sweep'}, sorted(names)
assert d['harness']['crush-signal']['harness'] == 'crush'
assert d['harness']['claude-code']['harness'] == 'claude-code'
# The drop-in directory is wired: without [server].harness_d the daemon never
# reads harness.d and every scheduled task silently stops existing.
assert d['server']['harness_d'].endswith('/.config/harness/harness.d'), d['server']
# All run with permission prompts off, so none may autostart on boot. The
# scheduled entries carry no enabled key at all (mutually exclusive with
# schedule); the daemon fires them only on their cron. The interactive three
# live in the main doc; a scheduled name may never appear there.
interactive = {'crush-signal', 'claude-code', 'claude-headless'}
assert set(d['harness']) == interactive, sorted(d['harness'])
for name in interactive:
    assert d['harness'][name]['enabled'] is False, name
PY"
  rm -rf "$_cfgdir" "$_cfgdir2"; [ "$status" -eq 0 ]
}

@test "harness: on a human login only pr-sweep declares a harness" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # The agent-only sweeps must render with NO [harness.*] table on a human
  # login, or Joe's box would run them too and Signal would double-report.
  # pr-sweep is the deliberate exception: it is the one sweep both identities
  # run, because the cross-identity review loop needs Joe approving the agent's
  # PRs on a schedule rather than by hand.
  #
  # The identity has to be PINNED, exactly like the agent cases pin ci-agent.
  # Without --config this renders as whoever runs the suite, so it asserted the
  # human gate while rendering as an agent on any -agent login - passing only
  # because CI happens to run as root. It failed for real on an agent box.
  _cfgdir="$(mktemp -d)"; _cfg="$_cfgdir/chezmoi.toml"
  printf '[data]
    agentIdentity = "ci"
' >"$_cfg"
  for _f in "$REPO_ROOT"/dot_config/harness/harness.d/*.toml.tmpl; do
    run bash -c "chezmoi execute-template --config '$_cfg' --source '$REPO_ROOT' < '$_f' | grep -c '^\[harness\.' || true"
    case "$(basename "$_f")" in
      pr-sweep.toml.tmpl) [ "$output" -eq 1 ] ;;
      *)                  [ "$output" -eq 0 ] ;;
    esac
  done
  rm -rf "$_cfgdir"
}

@test "harness: a human-login drop-in still renders NON-empty (chezmoi keeps the file)" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # This is the landmine under the gate above, and it is why the drop-ins carry
  # their comment header OUTSIDE the {{ if }}.
  #
  # chezmoi does not write a file whose template renders to nothing - it
  # removes it. If all three drop-ins ever rendered truly empty, human boxes
  # would end up with no harness.d directory at all, and [server] harness_d
  # pointing at a missing directory is a HARD config-load error upstream
  # ("[server] harness_d ...: no such file or directory") - it takes down the
  # whole harness config, not just the sweeps.
  #
  # So the comment header is load-bearing, not decoration. Pin it.
  _cfgdir="$(mktemp -d)"; _cfg="$_cfgdir/chezmoi.toml"
  printf '[data]
    agentIdentity = "ci"
' >"$_cfg"
  for _f in "$REPO_ROOT"/dot_config/harness/harness.d/*.toml.tmpl; do
    run bash -c "chezmoi execute-template --config '$_cfg' --source '$REPO_ROOT' < '$_f' | wc -c"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]
  done
  rm -rf "$_cfgdir"
}

@test "harness: every harness pins an explicit restart policy and a non-zero delay" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # Both keys used to be omitted, and the default restart_delay is 0 - an
  # instant respawn. The daemon gives up after 3 exits in a 10s window plus 5
  # backoff attempts and latches FAILED, which is terminal, so a fast-failing
  # agent was permanently gone in ~30s with nobody at a desk to notice. The
  # delay must stay wider than that 10s crash window's per-retry spacing, so a
  # transient upstream failure is retried instead of latching.
  # EXCEPTION - scheduled one-shots: config validation rejects restart=always
  # (respawning a one-shot after its clean exit makes the schedule meaningless);
  # they pin on-failure so a crashed run retries, and need no delay. They live
  # in the harness.d drop-ins now, so the check walks the concatenated render.
  # mktemp --suffix is GNU-only; BSD/macOS mktemp rejects it. chezmoi infers
  # the config format from the extension, so mint the .toml inside a temp dir.
  _cfgdir="$(mktemp -d)"; _cfgdir2="$(mktemp -d)"; _cfg="$_cfgdir2/chezmoi.toml"
  printf '[data]
    agentIdentity = "ci-agent"
' >"$_cfg"
  _render_all() {
    chezmoi execute-template --config "$_cfg" --source "$REPO_ROOT"       < "$HARNESS_TOML" > "$_cfgdir/00-main.toml"
    for _f in "$REPO_ROOT"/dot_config/harness/harness.d/*.toml.tmpl; do
      _n="$(basename "$_f" .toml.tmpl)"
      chezmoi execute-template --config "$_cfg" --source "$REPO_ROOT"         < "$_f" > "$_cfgdir/$_n.toml" || return 1
    done
  }
  run _render_all
  [ "$status" -eq 0 ]
  run bash -c "python3 - '$_cfgdir' <<'PY'
import glob, os, sys, tomllib
cfgdir = sys.argv[1]
harnesses = {}
for p in sorted(glob.glob(cfgdir + '/*.toml')):
    harnesses.update(tomllib.load(open(p, 'rb'))['harness'])
for name, h in harnesses.items():
    if 'schedule' in h:
        assert h.get('restart') in ('no', 'on-failure'), (name, h.get('restart'))
    else:
        assert h.get('restart') == 'always', (name, h.get('restart'))
        assert h.get('restart_delay', 0) >= 5, (name, h.get('restart_delay'))
PY"
  rm -rf "$_cfgdir" "$_cfgdir2"; [ "$status" -eq 0 ]
}

@test "harness: claude-code is Remote Control + skip-permissions, no Signal wiring" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # The phone drives this one through Remote Control, not the Signal channel: the
  # signal MCP in ~/.claude.json is wired WITHOUT --channel, and crush-signal now
  # answers every trusted-sender message unprefixed. An env_file here would be the
  # tell that someone gave claude a channel too — which now guarantees duplicate
  # replies, since neither agent would be filtering.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$HARNESS_TOML' | python3 -c '
import tomllib,sys
h = tomllib.load(sys.stdin.buffer)[\"harness\"][\"claude-code\"]
assert \"--remote-control\" in h[\"args\"], h[\"args\"]
assert \"--dangerously-skip-permissions\" in h[\"args\"], h[\"args\"]
assert h[\"workdir\"].endswith(\"/src\"), h[\"workdir\"]
assert \"env_file\" not in h, h
'"
  [ "$status" -eq 0 ]
}

@test "harness: crush-signal runs --yolo with the signal MCP opted in as a channel" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render "$HARNESS_TOML"
  [ "$status" -eq 0 ]
  # Channels are CLI-only in crush (no config key), so they must live in args.
  [[ "$output" == *'"--yolo"'* ]]
  [[ "$output" == *'"--channels", "signal"'* ]]
}

@test "harness: crush-signal opts into the switchboard channel too" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # Without this opt-in the switchboard MCP's tools still work but its doorbell
  # notifications never reach the session — the queue fills silently. The
  # opt-in is CLI-only in the fork (no config key), so it must ride args.
  run _render "$HARNESS_TOML"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"--channels", "switchboard"'* ]]
}

@test "harness: every harness declares a kind from the enum (no cmd, no default)" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render "$HARNESS_TOML"
  [ "$status" -eq 0 ]
  # `harness` is required upstream and has no default, so a table that omits it
  # fails config load outright — and `cmd` is rejected as a removed key. Each
  # table must therefore carry exactly one kind, and no cmd may come back.
  tables="$(printf '%s\n' "$output" | grep -c '^\[harness\.')"
  kinds="$(printf '%s\n' "$output" | grep -cE '^harness = "(crush|claude-code|codex|generic)"')"
  [ "$tables" -ge 3 ]
  [ "$kinds" -eq "$tables" ]
  ! printf '%s\n' "$output" | grep -q '^cmd = '
}

@test "harness: the agent CLIs resolve on the daemon's PATH, not an absolute cmd" {
  # The enum runs a bare `crush` / `claude`, so ~/.local/bin must lead the PATH
  # both service units hand the daemon — that is what keeps pointing at the
  # claude shim (and its self-updates) working now that cmd is gone.
  grep -q 'PATH=%h/.local/bin' "$REPO_ROOT/dot_config/systemd/user/harness.service.tmpl"
  grep -q '.local/bin:' "$REPO_ROOT/Library/LaunchAgents/rocks.stump.harness.plist.tmpl"
}

@test "harness: env_file repoints CRUSH_GLOBAL_DATA at the model-pin dir" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render "$HARNESS_ENV"
  [ "$status" -eq 0 ]
  # Must point at the dir holding create_crush.json.tmpl's target, or the pin is inert.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$HARNESS_ENV' | grep -c '^CRUSH_GLOBAL_DATA=/.*/\.local/share/crush-signal\$'"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "harness: env_file carries no secrets (it is committed)" {
  run grep -nE "API_KEY *=|TOKEN *=|SECRET *=|PASSWORD *=" "$HARNESS_ENV"
  [ "$status" -ne 0 ]
}

@test "harness: the model pin is glm-5.2 on the zai provider, and never hyper" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # glm-5.2 is served by BOTH zai and hyper, so the provider must be pinned too.
  #
  # The always-on agent belongs on Z.ai specifically: Z.ai is quota-metered, so
  # a busy week degrades to a hard stop, while Hyper is pay-per-token and
  # degrades to a bill. Assert NEITHER slot points at hyper — the drift that
  # motivated this test moved both of them there at once.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$MODEL_PIN' | python3 -c '
import json,sys
m = json.load(sys.stdin)[\"models\"]
assert m[\"large\"] == {\"model\": \"glm-5.2\", \"provider\": \"zai\"}, m[\"large\"]
assert m[\"small\"][\"provider\"] == \"zai\", m[\"small\"]
assert all(v[\"provider\"] != \"hyper\" for v in m.values()), m
'"
  [ "$status" -eq 0 ]
}

@test "harness: the crush signal MCP renders identity-free" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # Identity (account, operator, prefix) is resolved by signal-mcp from its
  # RUNTIME env, provisioned per-user by OpenBao — the render carries none of
  # it, so the same file is correct on every box and for every identity.
  run env -u SIGNAL_MCP_PREFIX bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_JSON'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"--channel"'* ]]
  [[ "$output" != *'"--account"'* ]]
  [[ "$output" != *'"--operator"'* ]]
  [[ "$output" != *'"--prefix"'* ]]
  ! grep -E -- '\+[0-9]{8,}' <<<"$output" >/dev/null
}

@test "harness: SIGNAL_MCP_* env never leaks into the crush render" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run env SIGNAL_MCP_PREFIX=cc SIGNAL_MCP_ACCOUNT=+15550001111 bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_JSON'"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"cc"'* ]]
  ! grep -E -- '\+[0-9]{8,}' <<<"$output" >/dev/null
}

@test "harness: the signal prefix is gated on the identity role, not hardcoded" {
  # This used to be a flat `grep SIGNAL_MCP_PREFIX=cc`, which is exactly how both
  # deployments ended up with the prefix. On joestump-agent@ (tars) that made a
  # healthy agent look dead — `running`, zero restarts, clean doctor, and silent
  # to every unprefixed message — because that account IS the agent's and nobody
  # prefixes when writing to it. Pin the gate itself, same as the sweep's role
  # gate, so the structure survives whichever box CI runs on.
  grep -q 'hasSuffix "-agent"' "$HARNESS_ENV"
}

@test "harness: the prefix renders per role — absent for agent, cc for human" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  # Behavioral check with THIS machine's identity, following the same shape as
  # test/stumpcloud-sweep.bats' role gate.
  #
  #   agent login (joestump-agent, tars) — the Signal account IS the agent's, so
  #     every trusted-sender message is meant for it: NO prefix. Absent, not
  #     empty: signal-mcp treats unset and empty the same, but harness appends
  #     this file last and later duplicates shadow earlier ones (spawn.go
  #     buildEnv), so any line here — even an empty one — shadows OpenBao.
  #
  #   human login (joestump, kitt) — the account is Joe's own and its Note to
  #     Self carries #todo / #bookmark / #journal owned by other automations, so
  #     the agent takes only what is addressed to it: cc stays.
  rendered="$(_render "$HARNESS_ENV")"
  if [[ "$(whoami)" == *-agent ]]; then
    ! grep -qE '^[[:space:]]*SIGNAL_MCP_PREFIX' <<<"$rendered"
  else
    grep -qE '^SIGNAL_MCP_PREFIX=cc$' <<<"$rendered"
  fi
}

@test "harness: the channel-enabled MCP servers are actually named 'signal' and 'switchboard'" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  # crush matches --channels entries against MCP server names; a rename would
  # silently disable the channel.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$CRUSH_JSON' | python3 -c '
import json,sys
mcp = json.load(sys.stdin)[\"mcp\"]
assert \"signal\" in mcp, sorted(mcp)
assert \"switchboard\" in mcp, sorted(mcp)
'"
  [ "$status" -eq 0 ]
}

@test "harness: [server] SSH cockpit, allow-list and port both from the OpenBao harness bag" {
  # The SSH cockpit (ADR-0004/0008) is a full-typing surface on every box, so
  # BOTH knobs are sourced from OpenBao, not from this committed template:
  #   authorized_keys_file = the path Vault Agent renders from the
  #     harness_authorized_keys field of secret/users/$USER/harness
  #     (harness-ssh.ctmpl) — not an inline key, not a hand-edited file;
  #   listen port = HARNESS_SSH_PORT from the same bag, via
  #     secrets-static.env, with an UNPRIVILEGED default so a pre-secrets
  #     bootstrap render is still valid and the user daemon can bind it.
  # And it renders for EVERY identity, human or agent — Joe attaches too.
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  _cfgdir="$(mktemp -d)"; _cfgdir2="$(mktemp -d)"; _cfg="$_cfgdir2/chezmoi.toml"
  printf '[data]\n    agentIdentity = "ci-agent"\n' >"$_cfg"
  # No HARNESS_SSH_PORT in the environment: the default must kick in.
  run bash -c "env -u HARNESS_SSH_PORT chezmoi execute-template --config '$_cfg' --source '$REPO_ROOT' < '$HARNESS_TOML' | python3 -c '
import tomllib,sys
s = tomllib.load(sys.stdin.buffer)[\"server\"]
assert s[\"enabled\"] is True, s
port = int(s[\"listen\"].rsplit(\":\", 1)[1])
assert port > 1024, port
assert s[\"authorized_keys_file\"].endswith(\"/.ssh/harness_authorized_keys\"), s
assert \"key\" not in s, \"no inline keys — allow-list comes from Vault Agent only\"
'"
  rm -rf "$_cfgdir" "$_cfgdir2"; [ "$status" -eq 0 ]

  # HARNESS_SSH_PORT set (as Vault Agent exports it from the harness bag): the
  # listen line must carry it through. A render that IGNORED the env var would
  # silently move the port away from the one bao declares.
  run bash -c "HARNESS_SSH_PORT=24680 chezmoi execute-template --source '$REPO_ROOT' < '$HARNESS_TOML' | python3 -c '
import tomllib,sys
s = tomllib.load(sys.stdin.buffer)[\"server\"]
assert s[\"listen\"].endswith(\":24680\"), s[\"listen\"]
'"
  [ "$status" -eq 0 ]

  # And the same render for a plain human identity — the cockpit is not
  # agent-gated.
  run bash -c "chezmoi execute-template --source '$REPO_ROOT' < '$HARNESS_TOML' | python3 -c '
import tomllib,sys
assert tomllib.load(sys.stdin.buffer)[\"server\"][\"enabled\"] is True
'"
  [ "$status" -eq 0 ]
}

@test "harness: the cockpit allow-list is rendered from the dedicated harness bag, not the ssh bag" {
  # harness-ssh.ctmpl writes every *_authorized_keys field of
  # secret/users/$USER/harness to ~/.ssh/<field>, mirroring ssh-keys.ctmpl's
  # metadata-listing guard so a user with no harness bag writes nothing under
  # ~/.ssh. agent.hcl.tmpl must register it (unconditionally — public keys
  # only, so the vaultSshKeys blast-radius gate does not apply).
  Ctmpl="$REPO_ROOT/dot_config/private_vault/harness-ssh.ctmpl"
  [ -f "$Ctmpl" ]
  grep -q 'secret/data/users/%s/harness' "$Ctmpl"
  grep -q 'regexMatch "_authorized_keys' "$Ctmpl"
  grep -q '"0600"' "$Ctmpl"
  grep -q 'harness-ssh.ctmpl' "$REPO_ROOT/dot_config/private_vault/agent.hcl.tmpl"
  grep -q 'harness-ssh.manifest' "$REPO_ROOT/dot_config/private_vault/agent.hcl.tmpl"
}

@test "harness: the reload script's human branch uses ui-lib, not a raw echo" {
  # Both identity branches reload the daemon now (the [server] cockpit is not
  # agent-only), so the ui-lib source and the HARNESS_BIN lookup are hoisted out
  # of the branch. A raw `echo` in the middle of an apply is a bug per CLAUDE.md
  # — czu's output is gum-styled and a bare line breaks the column.
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  Reload="$REPO_ROOT/.chezmoiscripts/run_onchange_after_52-harness-reload.sh.tmpl"
  _cfgdir="$(mktemp -d)"; _cfgdir2="$(mktemp -d)"; _cfg="$_cfgdir2/chezmoi.toml"

  # Human identity: reloads, and says so through ui-lib.
  printf '[data]\n    agentIdentity = "ci-human"\n' >"$_cfg"
  run bash -c "chezmoi execute-template --config '$_cfg' --source '$REPO_ROOT' < '$Reload'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'ui-lib.sh'* ]]
  [[ "$output" == *'"$HARNESS_BIN" reload'* ]]
  # The only `echo "    - …"` allowed is inside ui-lib's own fallback stub.
  [[ "$output" == *'item ok "harness daemon reloaded'* ]]
  [[ "$output" != *'echo "    - harness'* ]]

  # Agent identity: same hoisted preamble, plus the sweep teardown.
  printf '[data]\n    agentIdentity = "ci-agent"\n' >"$_cfg"
  run bash -c "chezmoi execute-template --config '$_cfg' --source '$REPO_ROOT' < '$Reload'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'ui-lib.sh'* ]]
  [[ "$output" == *'stumpcloud-sweep'* ]]
  rm -rf "$_cfgdir"

  # `harness reload` cannot bring the [server] listener up (the daemon calls
  # startRemote once at boot), so both branches must say restart, not reload.
  grep -q 'daemon RESTART, not a reload' "$Reload"
}

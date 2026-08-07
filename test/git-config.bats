#!/usr/bin/env bats
# Regression guard for dot_gitconfig.tmpl — ~/.gitconfig carries the git commit
# identity (name + email), derived from whoami using the $USER / $USER-agent
# convention, plus global defaults (init.defaultBranch, pull.rebase, etc.).
# These tests render the template and assert against the OUTPUT (what git reads).
# A second group renders against synthetic data to prove identity is genuinely
# derived from the username, not hardcoded.
load test_helper

GIT_TMPL="$REPO_ROOT/dot_gitconfig.tmpl"

# Render the real template (real .chezmoidata.yaml) into a variable. Skips when
# chezmoi isn't installed.
_render() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  chezmoi execute-template --source "$REPO_ROOT" < "$GIT_TMPL"
}

# Render with a specific .chezmoi.username by overriding the chezmoi data.
# This is what proves identity derives from whoami, not from a hardcoded value.
_render_as() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local username="$1"
  chezmoi execute-template --source "$REPO_ROOT" \
    --override-data "{\"chezmoi\":{\"username\":\"$username\"}}" \
    < "$GIT_TMPL"
}

# Render ~/.gitconfig + the GitHub include into a throwaway $HOME, create a repo
# with the given remote URL, and report the user.email REAL GIT resolves there.
# Asserting on git's own answer is the only way to catch an includeIf pattern
# that silently matches nothing — `git@github.com:**` looked right and matched
# NOTHING, because wildmatch only lets `**` span `/` between slashes.
_email_for_remote() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  local username="$1" url="$2"
  local sb="$BATS_TEST_TMPDIR/gitid-$$"
  rm -rf "$sb"; mkdir -p "$sb/home/.config/git" "$sb/repo"
  chezmoi execute-template --source "$REPO_ROOT" \
    --override-data "{\"chezmoi\":{\"username\":\"$username\",\"homeDir\":\"$sb/home\"}}" \
    < "$GIT_TMPL" > "$sb/home/.gitconfig"
  chezmoi execute-template --source "$REPO_ROOT" \
    < "$REPO_ROOT/dot_config/git/identity-github.tmpl" > "$sb/home/.config/git/identity-github"
  git -C "$sb/repo" init -q
  [ -n "$url" ] && git -C "$sb/repo" remote add origin "$url"
  HOME="$sb/home" XDG_CONFIG_HOME="$sb/home/.config" git -C "$sb/repo" config user.email
}

# ────── source layout ──────

@test "git-config: source is a dot_ template at repo root" {
  [ -f "$GIT_TMPL" ]
  basename "$GIT_TMPL" | grep -q '^dot_gitconfig\.tmpl$'
}

@test "git-config: template hardcodes no identity value" {
  # No address and no handle may be a literal here — the name derives from
  # whoami, every email comes from .gitEmail in .chezmoidata.yaml.
  run grep -Eic '@stump\.(wtf|rocks)|@joestump\.net|joestump' "$GIT_TMPL"
  [ "$output" -eq 0 ]
  grep -q '\.chezmoi\.username' "$GIT_TMPL"
  grep -q '\.gitEmail\.' "$GIT_TMPL"
}

@test "git-config: gitEmail declares all three forge addresses" {
  run chezmoi execute-template --source "$REPO_ROOT" \
    '{{ .gitEmail.agent }} {{ .gitEmail.gitea }} {{ .gitEmail.github }}'
  [ "$status" -eq 0 ]
  # Three distinct, real-looking addresses; the human's must not be an invented
  # <login>@stump.wtf, which no forge would have registered.
  local n
  n="$(tr ' ' '\n' <<< "$output" | grep -cE '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]+$')"
  [ "$n" -eq 3 ]
  [ "$(tr ' ' '\n' <<< "$output" | sort -u | wc -l)" -eq 3 ]
}

# ────── rendered output: per-forge identity, as REAL GIT resolves it ──────

@test "git-config: human commits to Gitea as the Gitea address" {
  [ "$(_email_for_remote joestump https://gitea.stump.rocks/joestump/dotfiles.git)" \
    = "$(chezmoi execute-template --source "$REPO_ROOT" '{{ .gitEmail.gitea }}')" ]
}

@test "git-config: human commits to GitHub as the GitHub address (https remote)" {
  [ "$(_email_for_remote joestump https://github.com/joestump/claude-ops.git)" \
    = "$(chezmoi execute-template --source "$REPO_ROOT" '{{ .gitEmail.github }}')" ]
}

@test "git-config: human commits to GitHub as the GitHub address (scp-style ssh remote)" {
  # The case that caught the bad glob: `git@github.com:**` matches NOTHING, so
  # every SSH-remote GitHub repo silently kept the Gitea address.
  [ "$(_email_for_remote joestump git@github.com:joestump/claude-ops.git)" \
    = "$(chezmoi execute-template --source "$REPO_ROOT" '{{ .gitEmail.github }}')" ]
}

@test "git-config: human commits to GitHub as the GitHub address (ssh:// remote)" {
  [ "$(_email_for_remote joestump ssh://git@github.com/joestump/claude-ops.git)" \
    = "$(chezmoi execute-template --source "$REPO_ROOT" '{{ .gitEmail.github }}')" ]
}

@test "git-config: a repo with no remote falls back to the Gitea address" {
  [ "$(_email_for_remote joestump "")" \
    = "$(chezmoi execute-template --source "$REPO_ROOT" '{{ .gitEmail.gitea }}')" ]
}

@test "git-config: agent uses one address on every forge" {
  local want
  want="$(chezmoi execute-template --source "$REPO_ROOT" '{{ .gitEmail.agent }}')"
  [ "$(_email_for_remote joestump-agent https://gitea.stump.rocks/joestump/dotfiles.git)" = "$want" ]
  [ "$(_email_for_remote joestump-agent https://github.com/joestump/claude-ops.git)" = "$want" ]
  [ "$(_email_for_remote joestump-agent git@github.com:joestump/claude-ops.git)" = "$want" ]
}

@test "git-config: agent renders no per-forge include at all" {
  run _render_as "joestump-agent"
  [ "$status" -eq 0 ]
  [[ "$output" != *"includeIf"* ]]
}

# ────── rendered output: identity derivation ──────

@test "git-config: renders without error" {
  run _render
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "git-config: agent user gets agent identity" {
  run _render_as "joestump-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = joestump-agent"* ]]
  [[ "$output" == *"email = agent@stump.wtf"* ]]
}

@test "git-config: human user gets the Gitea address as the base identity" {
  local want
  want="$(chezmoi execute-template --source "$REPO_ROOT" '{{ .gitEmail.gitea }}')"
  [ -n "$want" ]
  run _render_as "joestump"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = joestump"* ]]
  [[ "$output" == *"email = $want"* ]]
}

@test "git-config: agent email strips suffix from any human name" {
  # The convention is <human>-agent; the agent email local-part is always
  # 'agent', regardless of the human name.
  run _render_as "alice-agent"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = alice-agent"* ]]
  [[ "$output" == *"email = agent@stump.wtf"* ]]
}

@test "git-config: any non-agent login gets the same human email" {
  # The email is an account-level fact, not a per-login derivation: one human,
  # one registered address per forge, whatever the OS login happens to be. Only
  # the NAME follows whoami.
  local want
  want="$(chezmoi execute-template --source "$REPO_ROOT" '{{ .gitEmail.gitea }}')"
  [ -n "$want" ]
  run _render_as "alice"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name = alice"* ]]
  [[ "$output" == *"email = $want"* ]]
}

# ────── rendered output: global defaults ──────

@test "git-config: init.defaultBranch is main" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"defaultBranch = main"* ]]
}

@test "git-config: pull.rebase is true (never merge main into branch)" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"rebase = true"* ]]
}

@test "git-config: push.autoSetupRemote is true" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"autoSetupRemote = true"* ]]
}

@test "git-config: NO generic credential helper (would defeat the Gitea reset)" {
  # ~/.config/git/config is read BEFORE ~/.gitconfig, so its `helper = ""` reset
  # for gitea.stump.rocks cannot clear a helper declared here — a generic helper
  # gets APPENDED to the Gitea chain and, because git calls `approve` on every
  # helper in it, persists the rotating OpenBao token to plaintext
  # ~/.git-credentials. Bootstrap does not need one: czinit sets a temporary
  # host-scoped store, and credential-gitea.sh falls back to ~/.git-credentials.
  run _render
  [ "$status" -eq 0 ]
  # No bare [credential] section, and no unscoped `helper =` line.
  ! grep -qE '^\[credential\]$' <<< "$output"
  [[ "$output" != *"helper = store"* ]]
}

@test "git-config: GitHub gh auth credential helper present" {
  run _render
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh auth git-credential"* ]]
}

@test "git-config: gh path is resolved, not hardcoded to one OS" {
  # gh lives at /opt/homebrew/bin/gh on macOS and /usr/bin/gh on Debian/Ubuntu.
  # A hardcoded path breaks GitHub HTTPS auth on the other platform, so the
  # template must resolve it with lookPath.
  grep -q 'lookPath "gh"' "$GIT_TMPL"
  ! grep -q '!/usr/bin/gh auth git-credential' "$GIT_TMPL"
  # The rendered helper must point at a gh that actually exists on this box.
  run _render
  [ "$status" -eq 0 ]
  local gh_path
  gh_path="$(sed -n 's#^[[:space:]]*helper = !\(.*\) auth git-credential$#\1#p' <<< "$output" | head -1)"
  [ -n "$gh_path" ]
  if command -v gh >/dev/null 2>&1; then
    [ "$gh_path" = "$(command -v gh)" ]
  fi
}

@test "git-config: czu reasserts ~/.gitconfig (git config --global rewrites it)" {
  # `git config --global` writes ~/.gitconfig in place — czinit does it during
  # bootstrap, `gh auth setup-git` does it, humans do it. That trips chezmoi's
  # changed-since-last-write guard, after which the scheduled (no-TTY) apply
  # silently skips the file. czu must force-reassert it, like crush.json.
  grep -q '"\$HOME/\.gitconfig"' "$REPO_ROOT/dot_config/dotfiles/executable_czu-run.zsh"
}

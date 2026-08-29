#!/usr/bin/env bats
# Tests for custom/cookie-vault.zsh — browser cookies → OpenBao.
#
# The property that matters most here is NEGATIVE: the helper must never store,
# or print, cookies for domains the consumer does not need. A real
# `yt-dlp --cookies-from-browser chrome` on a daily driver exported 517 domains
# and 1,690 cookies — banking, email, work SSO — and the jar already sitting in
# secret/shared/youtube was found to carry binance.com, mintmobile.com and
# olukai.com. So the fixtures below deliberately include hostile neighbours, and
# the tests assert they are gone rather than asserting the wanted ones survive.
#
# Everything here is offline: the filter is pure text transformation, and the
# network-touching paths are exercised through stubs.
load test_helper

HELPER="$REPO_ROOT/dot_oh-my-zsh/custom/cookie-vault.zsh"

setup() { setup_stub_path; }

# A Netscape jar mixing YouTube auth cookies with things that must never leave
# the machine. Fields: domain, includeSubdomains, path, secure, expiry, name, value
_mixed_jar() {
  local f="$BATS_TEST_TMPDIR/raw.txt"
  {
    printf '# Netscape HTTP Cookie File\n\n'
    printf '.youtube.com\tTRUE\t/\tTRUE\t2000000000\tLOGIN_INFO\tyt-secret-value\n'
    printf '.google.com\tTRUE\t/\tTRUE\t2000000000\tSAPISID\tgoogle-secret-value\n'
    printf 'accounts.google.com\tFALSE\t/\tTRUE\t2000000000\tSID\taccounts-secret-value\n'
    printf '.binance.com\tTRUE\t/\tTRUE\t2000000000\tsession\tBINANCE-MUST-NOT-LEAK\n'
    printf '.schwab.com\tTRUE\t/\tTRUE\t2000000000\tauth\tSCHWAB-MUST-NOT-LEAK\n'
    printf 'mail.google.com\tFALSE\t/\tTRUE\t2000000000\tGMAIL\tGMAIL-MUST-NOT-LEAK\n'
    printf '.proton.me\tTRUE\t/\tTRUE\t2000000000\tps\tPROTON-MUST-NOT-LEAK\n'
  } > "$f"
  printf '%s' "$f"
}

# The regex the youtube profile ships with, kept in one place here so a change
# to the profile shows up as a test failure rather than a silent widening.
YT_RE='^\.?(youtube\.com|google\.com|accounts\.google\.com)$'

_filter_to() {
  local in="$1" out="$2"
  zsh -c "source '$HELPER'; _cookie_vault_filter '$in' '$YT_RE' '$out'"
}

# ----- the filter: what it keeps -----

@test "filter keeps the YouTube and Google auth domains" {
  local raw out; raw="$(_mixed_jar)"; out="$BATS_TEST_TMPDIR/out.txt"
  run _filter_to "$raw" "$out"
  [ "$status" -eq 0 ]
  grep -q '^\.youtube\.com' "$out"
  grep -q '^\.google\.com' "$out"
  grep -q '^accounts\.google\.com' "$out"
}

@test "filter emits a valid Netscape header" {
  local raw out; raw="$(_mixed_jar)"; out="$BATS_TEST_TMPDIR/out.txt"
  _filter_to "$raw" "$out"
  [ "$(head -1 "$out")" = "# Netscape HTTP Cookie File" ]
}

@test "filtered jar keeps all 7 tab-separated fields per cookie" {
  local raw out; raw="$(_mixed_jar)"; out="$BATS_TEST_TMPDIR/out.txt"
  _filter_to "$raw" "$out"
  run awk -F'\t' '!/^#/ && NF && NF != 7 {bad++} END {print bad+0}' "$out"
  [ "$output" = "0" ]
}

# ----- the filter: what it must drop (the point of the exercise) -----

@test "filter drops banking, email and unrelated domains" {
  local raw out; raw="$(_mixed_jar)"; out="$BATS_TEST_TMPDIR/out.txt"
  _filter_to "$raw" "$out"
  ! grep -q 'binance' "$out"
  ! grep -q 'schwab' "$out"
  ! grep -q 'proton' "$out"
  ! grep -q 'mail\.google\.com' "$out"
}

@test "no MUST-NOT-LEAK value survives the filter" {
  local raw out; raw="$(_mixed_jar)"; out="$BATS_TEST_TMPDIR/out.txt"
  _filter_to "$raw" "$out"
  ! grep -q 'MUST-NOT-LEAK' "$out"
}

@test "filter is not fooled by a lookalike domain suffix" {
  local raw="$BATS_TEST_TMPDIR/evil.txt" out="$BATS_TEST_TMPDIR/out.txt"
  {
    printf '# Netscape HTTP Cookie File\n\n'
    printf '.notyoutube.com\tTRUE\t/\tTRUE\t2000000000\tx\tEVIL\n'
    printf '.youtube.com.evil.tld\tTRUE\t/\tTRUE\t2000000000\ty\tEVIL\n'
    printf '.youtube.com\tTRUE\t/\tTRUE\t2000000000\tLOGIN_INFO\tgood\n'
  } > "$raw"
  _filter_to "$raw" "$out"
  ! grep -q 'EVIL' "$out"
  grep -q 'LOGIN_INFO' "$out"
}

@test "filter fails when nothing matches, rather than storing an empty jar" {
  local raw="$BATS_TEST_TMPDIR/none.txt" out="$BATS_TEST_TMPDIR/out.txt"
  {
    printf '# Netscape HTTP Cookie File\n\n'
    printf '.binance.com\tTRUE\t/\tTRUE\t2000000000\tsession\tnope\n'
  } > "$raw"
  run _filter_to "$raw" "$out"
  [ "$status" -ne 0 ]
}

# ----- reporting never reveals a value -----

@test "describe reports metadata only — no cookie values" {
  local raw; raw="$(_mixed_jar)"
  run zsh -c "source '$HELPER'; _cookie_vault_describe '$raw'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cookies="* ]]
  [[ "$output" == *"domains="* ]]
  ! [[ "$output" == *"MUST-NOT-LEAK"* ]]
  ! [[ "$output" == *"yt-secret-value"* ]]
  ! [[ "$output" == *"google-secret-value"* ]]
}

@test "fingerprint is truncated, not a full hash" {
  local raw; raw="$(_mixed_jar)"
  run zsh -c "source '$HELPER'; _cookie_vault_fingerprint '$raw'"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 16 ]
}

# ----- profile registry -----

@test "the youtube profile targets the shared path both consumers read" {
  # Pinchflat (ie02) and Jellyfin's YoutubeMetadata (ie01) are on different
  # hosts, so a per-host path cannot serve both; shared/ is the only path the
  # converge policy can read for both. The key name must match what the live
  # secret actually uses — it is `cookies`, not `YOUTUBE_COOKIES`, and getting
  # that wrong resolves to nothing and silently installs no cookies at all.
  run zsh -c "source '$HELPER'; print -r -- \$COOKIE_VAULT_PATH[youtube]; print -r -- \$COOKIE_VAULT_KEY[youtube]"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "shared/youtube" ]
  [ "${lines[1]}" = "cookies" ]
}

@test "an unknown profile is refused" {
  run zsh -c "source '$HELPER'; cookie-vault push definitely-not-a-profile"
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown profile"* ]]
}

# ----- push pre-flight -----

@test "push refuses when the token cannot write the path" {
  # The AppRole has read+list on secret/shared/* and nothing more; discovering
  # that AFTER extraction would waste a macOS Keychain prompt.
  make_stub vault 'echo "read, list"'
  make_stub yt-dlp 'exit 0'
  run zsh -c "source '$HELPER'; cookie-vault push youtube"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot write"* ]]
  [[ "$output" == *"vault-oidc-login"* ]]
}

@test "push aborts when the browser produced no jar" {
  make_stub vault 'echo "create, read, update"'
  make_stub yt-dlp 'exit 0'   # writes nothing
  run zsh -c "source '$HELPER'; cookie-vault push youtube"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no jar produced"* ]]
}

@test "push refuses to store a jar that does not authenticate" {
  # The critical guard: yt-dlp presenting invalid credentials draws stricter
  # bot checks than an anonymous request, so a broken jar is worse than none.
  make_stub vault 'echo "create, read, update"'
  make_stub yt-dlp '
if [[ "$*" == *--cookies-from-browser* ]]; then
  for a in "$@"; do [[ $prev == --cookies ]] && out=$a; prev=$a; done
  printf "# Netscape HTTP Cookie File\n\n.youtube.com\tTRUE\t/\tTRUE\t2000000000\tLOGIN_INFO\tv\n" > "$out"
  exit 0
fi
exit 1'   # the verification pass fails
  run zsh -c "source '$HELPER'; cookie-vault push youtube"
  [ "$status" -ne 0 ]
  [[ "$output" == *"did NOT authenticate"* ]]
  [[ "$output" == *"refusing to store"* ]]
}

@test "help lists the verbs" {
  run zsh -c "source '$HELPER'; cookie-vault --help"
  [ "$status" -eq 2 ]
  [[ "$output" == *"push"* ]]
  [[ "$output" == *"status"* ]]
  [[ "$output" == *"verify"* ]]
}

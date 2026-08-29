# Browser Cookies → OpenBao, Scoped And Verified
#
# Some self-hosted services need a logged-in browser session to do their job —
# Pinchflat and Jellyfin's YoutubeMetadata plugin both feed a Netscape cookie
# jar to yt-dlp, because YouTube answers an anonymous request with "Sign in to
# confirm you're not a bot". Those jars go stale, and refreshing them by hand
# (export extension → download → paste into OpenBao) is the kind of chore that
# silently stops happening.
#
# `cookie-vault push youtube` does the whole loop: pull cookies straight from
# the browser, cut them down to the domains the consumer actually needs, prove
# the result still authenticates, and only then write it to OpenBao.
#
# Three things this deliberately does NOT do:
#
#   * It never prints a cookie value. Everything it reports is metadata —
#     counts, domains, a truncated SHA-256. A jar that reaches a terminal is a
#     jar in a scrollback buffer, a transcript, and probably a model context.
#   * It never stores an unfiltered jar. `yt-dlp --cookies-from-browser chrome`
#     on a daily driver exports EVERY domain the browser holds — measured at
#     517 domains / 1,690 cookies here, including schwab.com, etrade.com,
#     mail.google.com and proton.me. Storing that to fix a YouTube downloader
#     would put banking and email sessions in a secret half the fleet can read.
#     Filtering to the auth domains cuts it to ~14 KB and keeps every one of the
#     42 cookies that actually carry the session.
#   * It never stores a jar it could not verify. A silently-invalid jar is worse
#     than none: yt-dlp presenting broken credentials gets stricter treatment
#     from YouTube than an anonymous request.
#
# Why yt-dlp is the extractor: it is already a dependency of every consumer, it
# emits Netscape jar format natively, and it handles Chrome's macOS Keychain
# decryption. barnardb/cookies (also installed) only emits `Cookie:` header
# format — fine for curl one-liners, but it drops domain/path/expiry/secure, so
# a jar cannot be reconstructed from its output.
#
# Writing requires the OIDC identity: `secret/shared/*` is read-only for the
# AppRole (see vault-token.zsh — bare $VAULT_TOKEN is the OIDC identity, admin
# if your group grants it). Run `vault-oidc-login` first.
#
# @joestump-agent 08/29/2026 - Created after Pinchflat's cookies were found
# unrefreshed since 2026-08-19, and the stored jar was found to contain
# binance.com, mintmobile.com and olukai.com alongside the YouTube session.

# Profile registry — one associative array per field.
#
# Deliberately NOT a single delimited string: the domain pattern contains `|`
# (it is an alternation), so any delimiter cheap enough to type is also a
# character the value legitimately holds. A packed "path|key|regex|url" spec
# silently truncated the pattern to `^\.?(youtube\.com` and awk rejected it.
# Four arrays cost a few lines and cannot be misparsed.
#
# Add a profile by adding one entry to each array; nothing else changes.
typeset -gA COOKIE_VAULT_PATH COOKIE_VAULT_KEY COOKIE_VAULT_DOMAINS COOKIE_VAULT_VERIFY_URL

# `shared/`, not a per-host path: Pinchflat (ie02) and Jellyfin's
# YoutubeMetadata plugin (ie01) are on different hosts, and converge's policy
# covers secret/data/shared/* but never secret/data/users/*.
COOKIE_VAULT_PATH[youtube]='shared/youtube'
COOKIE_VAULT_KEY[youtube]='cookies'
COOKIE_VAULT_DOMAINS[youtube]='^\.?(youtube\.com|google\.com|accounts\.google\.com)$'
COOKIE_VAULT_VERIFY_URL[youtube]='https://www.youtube.com/watch?v=dQw4w9WgXcQ' 

# Filter a Netscape jar down to the domains a profile needs.
#   _cookie_vault_filter <in-file> <domain-regex> <out-file>
# Pure text transformation — no network, no browser — so it is unit-testable.
# Emits a valid jar: the Netscape header, then only matching cookie lines.
# Netscape jar lines are 7 tab-separated fields:
#   domain  includeSubdomains  path  secure  expiry  name  value
_cookie_vault_filter() {
  local in="$1" re="$2" out="$3"
  [[ -r "$in" ]] || return 1
  {
    print -- '# Netscape HTTP Cookie File'
    print -- '# Filtered by cookie-vault: only the domains this consumer needs.'
    print --
    # ENVIRON, not -v: awk's -v processes backslash escapes, so `\.` would
    # arrive as `.` and match ANY character — `.youtubeXcom` would pass.
    COOKIE_VAULT_RE="$re" awk -F'\t' 'NF >= 7 && $1 ~ ENVIRON["COOKIE_VAULT_RE"]' "$in"
  } > "$out"
  # A jar with a header and no cookies is not useful — say so rather than
  # storing an empty shell that fails opaquely at the consumer.
  [[ -s "$out" ]] && [[ $(awk -F'\t' 'NF>=7' "$out" | wc -l) -gt 0 ]]
}

# Report on a jar without ever revealing one. Used by push and status alike.
_cookie_vault_describe() {
  local jar="$1" now
  now=$(date +%s)
  local bytes cookies domains expired
  bytes=$(wc -c < "$jar" | tr -d ' ')
  cookies=$(awk -F'\t' 'NF>=7' "$jar" | wc -l | tr -d ' ')
  domains=$(awk -F'\t' 'NF>=7 {print $1}' "$jar" | sort -u | wc -l | tr -d ' ')
  expired=$(awk -F'\t' -v n="$now" 'NF>=7 && $5+0 > 0 && $5+0 < n' "$jar" | wc -l | tr -d ' ')
  print -- "  bytes=${bytes} cookies=${cookies} domains=${domains} expired=${expired}"
  print -- "  domains: $(awk -F'\t' 'NF>=7 {print $1}' "$jar" | sort -u | tr '\n' ' ')"
  print -- "  sha256: $(_cookie_vault_fingerprint "$jar")"
}

# Truncated SHA-256 — enough to compare two jars, useless to an attacker.
_cookie_vault_fingerprint() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -c1-16
  else
    sha256sum "$1" | cut -c1-16
  fi
}

# Prove a jar still authenticates before it is allowed near OpenBao.
_cookie_vault_verify_jar() {
  local jar="$1" url="$2"
  yt-dlp --cookies "$jar" --simulate --quiet --no-warnings \
         --print '%(title)s' "$url" >/dev/null 2>&1
}

cookie-vault() {
  emulate -L zsh
  setopt local_options err_return no_unset

  local verb="${1:-}" profile="${2:-youtube}" browser="${COOKIE_VAULT_BROWSER:-chrome}"

  if [[ -z "$verb" || "$verb" == (-h|--help|help) ]]; then
    print -u2 "usage: cookie-vault {push|status|verify|profiles} [profile]"
    print -u2 "  push     extract from \$COOKIE_VAULT_BROWSER (default chrome), filter, verify, store"
    print -u2 "  status   describe the STORED jar (metadata only, never values)"
    print -u2 "  verify   fetch the stored jar and prove it still authenticates"
    print -u2 "  profiles list known profiles"
    return 2
  fi

  if [[ "$verb" == profiles ]]; then
    local p
    for p in ${(k)COOKIE_VAULT_PATH}; do
      print -- "  ${p} -> secret/${COOKIE_VAULT_PATH[$p]}:${COOKIE_VAULT_KEY[$p]}"
    done
    return 0
  fi

  local vpath="${COOKIE_VAULT_PATH[$profile]:-}"
  if [[ -z "$vpath" ]]; then
    print -u2 "cookie-vault: unknown profile '${profile}' (try: cookie-vault profiles)"
    return 2
  fi
  local vkey="${COOKIE_VAULT_KEY[$profile]}"
  local vre="${COOKIE_VAULT_DOMAINS[$profile]}"
  local vurl="${COOKIE_VAULT_VERIFY_URL[$profile]}"

  : "${VAULT_ADDR:=https://vault.stump.rocks}"
  export VAULT_ADDR

  # 0600 workspace, removed on every exit path including failure.
  local tmp; tmp=$(mktemp -d) || return 1
  chmod 700 "$tmp"
  trap "rm -rf -- '$tmp'" EXIT INT TERM

  case "$verb" in
    push)
      command -v yt-dlp >/dev/null 2>&1 || {
        print -u2 "cookie-vault: yt-dlp not installed (brew bundle --global)"; return 1; }

      # `vault token capabilities` is the honest pre-flight: the AppRole can
      # READ secret/shared/* but not write it, and discovering that after the
      # extraction wastes a Keychain prompt.
      local caps
      caps=$(vault token capabilities "secret/data/${vpath}" 2>/dev/null) || caps=""
      if [[ "$caps" != *update* && "$caps" != *create* && "$caps" != *root* ]]; then
        print -u2 "cookie-vault: this token cannot write secret/data/${vpath} (has: ${caps:-none})"
        print -u2 "              secret/shared/* is OIDC-admin only — run: vault-oidc-login"
        return 1
      fi

      print -- "→ extracting from ${browser} (a Keychain prompt is expected on macOS)"
      # yt-dlp writes the jar on exit; a non-zero rc from the probe URL is not
      # fatal so long as the jar landed, so the jar's existence is the test.
      yt-dlp --cookies-from-browser "$browser" --cookies "$tmp/raw.txt" \
             --simulate --quiet --no-warnings "$vurl" >/dev/null 2>&1 || true
      [[ -s "$tmp/raw.txt" ]] || {
        print -u2 "cookie-vault: no jar produced — is ${browser} installed and logged in?"; return 1; }

      local raw_c raw_d
      raw_c=$(awk -F'\t' 'NF>=7' "$tmp/raw.txt" | wc -l | tr -d ' ')
      raw_d=$(awk -F'\t' 'NF>=7 {print $1}' "$tmp/raw.txt" | sort -u | wc -l | tr -d ' ')
      print -- "  raw browser export: ${raw_c} cookies across ${raw_d} domains"

      _cookie_vault_filter "$tmp/raw.txt" "$vre" "$tmp/jar.txt" || {
        print -u2 "cookie-vault: filter matched no cookies — is the browser logged in to this service?"
        return 1; }
      print -- "→ filtered to the ${profile} auth domains"
      _cookie_vault_describe "$tmp/jar.txt"

      print -- "→ verifying the filtered jar still authenticates"
      if ! _cookie_vault_verify_jar "$tmp/jar.txt" "$vurl"; then
        print -u2 "cookie-vault: the filtered jar did NOT authenticate — refusing to store it."
        print -u2 "              A broken jar is worse than none: yt-dlp presenting invalid"
        print -u2 "              credentials draws stricter bot checks than an anonymous request."
        return 1
      fi
      print -- "  ✓ authenticated"

      vault kv put -mount=secret "$vpath" "${vkey}=@$tmp/jar.txt" >/dev/null || {
        print -u2 "cookie-vault: vault write failed"; return 1; }
      print -- "✓ stored at secret/${vpath}:${vkey}"
      print -- "  consumers pick it up on their next Ansible converge:"
      print -- "    ansible-playbook -i dub.yaml playbooks/services/youtube-cookies.yaml"
      ;;

    status)
      vault kv get -mount=secret -field="$vkey" "$vpath" > "$tmp/jar.txt" 2>/dev/null || {
        print -u2 "cookie-vault: cannot read secret/${vpath}:${vkey}"; return 1; }
      print -- "secret/${vpath}:${vkey}"
      _cookie_vault_describe "$tmp/jar.txt"
      vault kv metadata get -mount=secret -format=json "$vpath" 2>/dev/null \
        | jq -r '"  version=\(.data.current_version) updated=\(.data.updated_time)"' 2>/dev/null || true
      ;;

    verify)
      vault kv get -mount=secret -field="$vkey" "$vpath" > "$tmp/jar.txt" 2>/dev/null || {
        print -u2 "cookie-vault: cannot read secret/${vpath}:${vkey}"; return 1; }
      _cookie_vault_describe "$tmp/jar.txt"
      if _cookie_vault_verify_jar "$tmp/jar.txt" "$vurl"; then
        print -- "✓ the stored jar authenticates"
      else
        print -u2 "✗ the stored jar does NOT authenticate — run: cookie-vault push ${profile}"
        return 1
      fi
      ;;

    *)
      print -u2 "cookie-vault: unknown verb '${verb}' (try: cookie-vault --help)"
      return 2
      ;;
  esac
}

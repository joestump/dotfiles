# GITHUB_TOKEN must not shadow gh's stored keychain credential.
#
# A fine-grained PAT exported from OpenBao as GITHUB_TOKEN made every `gh`
# call 403 on PR creation (2026-09-04): GITHUB_TOKEN in the environment
# unconditionally overrides gh's own keychain auth. The loader must drop
# GITHUB_TOKEN when gh can authenticate from its own stored credential.

load test_helper

SECRETS_LOADER="$REPO_ROOT/dot_oh-my-zsh/custom/00-secrets.zsh"

@test "00-secrets.zsh exists and references the gh fallback guard" {
    [ -f "$SECRETS_LOADER" ]
    grep -q 'unset GITHUB_TOKEN' "$SECRETS_LOADER"
}

@test "guard only drops GITHUB_TOKEN when gh has stored auth" {
    # Guard is conditional on `gh auth token` succeeding — headless machines
    # with no keychain credential keep the OpenBao-exported token.
    grep -q 'command -v gh' "$SECRETS_LOADER"
    grep -q 'gh auth token' "$SECRETS_LOADER"
}

@test "GITHUB_PERSONAL_ACCESS_TOKEN is not unset (other tooling reads it)" {
    if grep -q 'unset GITHUB_PERSONAL_ACCESS_TOKEN' "$SECRETS_LOADER"; then
        fail "GITHUB_PERSONAL_ACCESS_TOKEN must stay exported"
    fi
}

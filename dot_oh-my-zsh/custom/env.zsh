# Environment variables — static, plus a few derived from secrets.
#
# Loads AFTER 00-secrets.zsh (the secrets loader sorts first), so vars here may
# reference secrets the Vault Agent rendered from OpenBao — e.g. $LITELLM_API_KEY
# (from secret/personal/llm). The secret VALUES never live in this file or the
# repo; only $VAR references do.

# OpenBao endpoint — set unconditionally so it's available even on a fresh node,
# before any secrets exist (you need it to `vault login` the very first time).
export VAULT_ADDR="https://vault.stump.rocks"

# Route ALL OpenAI-compatible tooling through the self-hosted LiteLLM gateway.
# (On a fresh node before `vault login`, $LITELLM_API_KEY is empty and these are
# inert until secrets render — exactly what we want.)
export OPENAI_BASE_URL="https://litellm.stump.rocks/v1"
export OPENAI_API_KEY="$LITELLM_API_KEY"

# zsh-ai's OpenAI provider → same gateway. URL is derived from OPENAI_BASE_URL
# (which already includes the scheme + /v1), so no double "https://".
export ZSH_AI_OPENAI_URL="${OPENAI_BASE_URL}/chat/completions"
export ZSH_AI_OPENAI_API_KEY="$LITELLM_API_KEY"
export ZSH_AI_OPENAI_MODEL="gpt-oss:120b"

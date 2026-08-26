# Uniform entry points (`make test` / `make lint` / `make check`) so neither a
# human nor an agent has to rediscover the incantation per repo. `test` is the
# exact suite CI's bats job runs.
#
# `lint` is the full local gate: a secret scan plus `lint-shell`. `lint-shell`
# is the whole shell lint — shellcheck over the plain scripts AND over every
# rendered chezmoi `*.sh.tmpl`, across its gate variants — and it is what CI's
# lint job calls, so a green `make lint-shell` locally means what it means
# there. CI scans for secrets in its own dedicated gitleaks workflow rather
# than through this target, which is why the split exists.
#
# `lint` needs chezmoi, shellcheck and gitleaks on PATH; `lint-shell` drops the
# gitleaks requirement.
.PHONY: test lint lint-shell check

test:
	bats --print-output-on-failure test/

lint: lint-shell
	gitleaks git --redact --no-banner .

lint-shell:
	./scripts/lint-shell.sh

check: test lint

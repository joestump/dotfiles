# Uniform entry points (`make test` / `make lint` / `make check`) so neither a
# human nor an agent has to rediscover the incantation per repo. `test` is the
# exact suite CI's bats job runs. `lint` is the locally-runnable core — secret
# scan + shellcheck over the plain (non-template) scripts; the render-based
# template lint matrix stays in the CI lint job (.gitea/workflows/ci.yml),
# which needs a full chezmoi toolchain.
.PHONY: test lint check

test:
	bats --print-output-on-failure test/

lint:
	gitleaks git --redact --no-banner .
	git ls-files 'scripts/*.sh' 'run_*.sh' 'dot_config/dotfiles/*.sh' '.githooks/pre-commit' '.chezmoiscripts/*.sh' \
		| xargs -r shellcheck -x -e SC1091

check: test lint

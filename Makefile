SHELLCHECK := ./bin/shellcheck
SCRIPTS    := setup.sh scripts/start.sh scripts/healthcheck.sh scripts/env-manager.sh

.PHONY: lint test clean

lint:
	$(SHELLCHECK) -s bash $(SCRIPTS)

test: lint
	@echo "All checks passed."

clean:
	rm -rf bin/
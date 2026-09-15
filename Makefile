.DEFAULT_GOAL := check
.PHONY: check test build package clean

# Example: make test ARGS='--derived-data "/private/tmp/lens-derived-data.ABC123"'
check test build package clean:
	@bash scripts/lens.sh $@ $(ARGS)

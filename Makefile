.PHONY: test test-file help

test:
	busted

test-file:
	busted $(FILE)

help:
	@echo "Usage:"
	@echo "  make test           - run all specs"
	@echo "  make test-file FILE=spec/foo_spec.lua  - run a single spec"

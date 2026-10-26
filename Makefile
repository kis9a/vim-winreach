.DEFAULT_GOAL := help
SHELL := /bin/bash

PWD := $(shell realpath $(dir $(lastword $(MAKEFILE_LIST))))
DEPS_DIR := $(PWD)/.deps

.PHONY: init deps tester linter lint test test-nvim help clean
.PHONY: lint-vint vint-int check-vint

THEMIS_URL    := https://github.com/thinca/vim-themis.git
THEMIS_DIR    := $(DEPS_DIR)/vim-themis
THEMIS_COMMIT := 355c34b1bff03a8fd3744e3ad2dd0627c0692716

VIMLPARSER_URL    := https://github.com/ynkdir/vim-vimlparser.git
VIMLPARSER_DIR    := $(DEPS_DIR)/vim-vimlparser
VIMLPARSER_COMMIT := 4495d3957dbf84d8c8f9a58abe021d1554aec631

VIMLINT_URL    := https://github.com/syngan/vim-vimlint.git
VIMLINT_DIR    := $(DEPS_DIR)/vim-vimlint
VIMLINT_COMMIT := cec40c28f119a5f4b92ceb0b6aae525122a81244

LINT_DIRS ?= autoload plugin test

# autoload/winreach/winref.vim is vendored from kis9a/vim-winref under this
# plugin's own namespace (two plugins shipping the same autoload/winref.vim
# would shadow each other on 'runtimepath').  Do not edit it here; regenerate
# it with 'make vendor' in the vim-winref checkout.

define CLONE_AND_OPTIONAL_PIN
	@set -euo pipefail; \
	url="$(1)"; dir="$(2)"; commit="$(3)"; \
	mkdir -p "$(DEPS_DIR)"; \
	if [ ! -d "$$dir/.git" ]; then \
		git clone "$$url" "$$dir"; \
	fi; \
	if [[ "$$commit" =~ ^[0-9a-fA-F]{7,40}$$ ]]; then \
		git -C "$$dir" checkout -q --detach "$$commit"; \
	fi; \
	echo "OK: $$dir @ $$(git -C "$$dir" rev-parse --short HEAD)"
endef

init: linter tester ## init

deps: tester linter ## clone deps (optionally pin)

tester: $(THEMIS_DIR) ## clone tester

linter: $(VIMLPARSER_DIR) $(VIMLINT_DIR) ## clone linter

$(THEMIS_DIR):
	$(call CLONE_AND_OPTIONAL_PIN,$(THEMIS_URL),$(THEMIS_DIR),$(THEMIS_COMMIT))

$(VIMLPARSER_DIR):
	$(call CLONE_AND_OPTIONAL_PIN,$(VIMLPARSER_URL),$(VIMLPARSER_DIR),$(VIMLPARSER_COMMIT))

$(VIMLINT_DIR):
	$(call CLONE_AND_OPTIONAL_PIN,$(VIMLINT_URL),$(VIMLINT_DIR),$(VIMLINT_COMMIT))

test: tester ## testing with vim-themis (Vim)
	$(THEMIS_DIR)/bin/themis --reporter spec -r test

test-nvim: tester ## testing with vim-themis (Neovim)
	THEMIS_VIM=nvim \
	THEMIS_ARGS='--headless -u NONE -i NONE -n' \
	$(THEMIS_DIR)/bin/themis --reporter spec -r test

# vimlint.sh's -c/-e handlers rely on GNU sed's \+ (unsupported by BSD sed),
# so on macOS the generated config is invalid VimL: every run exits 1 before
# reporting anything and func_abort=1 is silently dropped.  Invoke vimlint
# directly with the same config instead.
# EVL108 is suppressed: it predates version features like has('nvim-0.9').
LINT_CONFIG := {'quiet': 1, 'func_abort': 1, 'EVL102': {'l:_': 1}, 'EVL103': {':': 1}, 'EVL108': {':': 1}}

lint: linter ## linting with vimlint
	@ret=0; \
	for d in $(LINT_DIRS); do \
		tf=$$(mktemp); \
		vim -u NONE -i NONE -es -N \
			-c "set rtp+=$(VIMLINT_DIR)" -c "set rtp+=$(VIMLPARSER_DIR)" \
			-c "let g:vimlint#config = $(LINT_CONFIG)" \
			-c "call vimlint#vimlint('$$d', {'output': '$$tf'})" -c 'qall!' \
			< /dev/null || { echo "vim exited non-zero linting $$d"; ret=1; }; \
		grep -a -w -E 'Error|Warning' "$$tf" | grep -v EVP_0 && ret=2; \
		grep -a EVP_0 "$$tf" | sed 's/^/NOTE upstream vimlint internal error (not a finding): /'; \
		rm -f "$$tf"; \
	done; \
	exit $$ret

lint-vint: check-vint ## linting with vint
	vint autoload plugin test

vint-int: ## install vint using pip
	pip install vint

check-vint: ## check vint command exists
	command -v vint >/dev/null 2>&1

clean: ## remove cloned deps
	rm -rf $(DEPS_DIR)

help: ## help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

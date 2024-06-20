GITHUB_REPO := vigetlabs/terraform-aws-waf

.DEFAULT_GOAL = help
EXECUTABLE_DEPS = terraform-docs

# Test for executable dependencies
K := $(foreach exec,$(EXECUTABLE_DEPS),\
				$(if $(shell which $(exec)), "$(exec) found" , $(error "No $(exec) in PATH")))

.PHONY: help docs

## This help screen
help:
	@printf "Available targets:\n\n"
	@awk '/^[a-zA-Z\-\_0-9%:\\]+/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = $$1; \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
	gsub("\\\\", "", helpCommand); \
	gsub(":+$$", "", helpCommand); \
			printf "  \x1b[32;01m%-35s\x1b[0m %s\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST) | sort -u
	@printf "\n"

## Generate terraform documentation and add to README.md
docs:
	terraform-docs -c .terraform.docs.yml .

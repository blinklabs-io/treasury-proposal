# Blink Treasury Proposal - Makefile
# Usage: make [target] [NETWORK=preview|preprod|mainnet] [CARDANO_CLI=cardano-cli]

NETWORK   ?= preview
CARDANO_CLI ?= cardano-cli

# Network flag logic
ifeq ($(NETWORK),mainnet)
  NETWORK_FLAG := --mainnet
else ifeq ($(NETWORK),preprod)
  NETWORK_FLAG := --testnet-magic 1
else
  NETWORK_FLAG := --testnet-magic 2
endif

.PHONY: help check-prereqs generate-test-keys metadata hash governance-action build-tx sign-tx \
        submit-testnet submit-mainnet test-lifecycle report journal-entry clean

help: ## Show all available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-prereqs: ## Run prerequisite checks
	scripts/check-prereqs.sh

generate-test-keys: ## Generate a fresh wallet for preview testnet
	scripts/generate-test-keys.sh

metadata: ## Generate proposal metadata
	scripts/generate-metadata.sh

hash: ## Hash the proposal metadata JSON
	scripts/hash-metadata.sh metadata/proposal-metadata.json

governance-action: hash ## Create the governance action (depends on hash)
	scripts/create-governance-action.sh $(NETWORK_FLAG)

build-tx: governance-action ## Build the transaction (depends on governance-action)
	scripts/build-tx.sh $(NETWORK_FLAG)

sign-tx: build-tx ## Sign the transaction (depends on build-tx)
	scripts/sign-tx.sh $(NETWORK_FLAG)

submit-testnet: NETWORK = preview
submit-testnet: NETWORK_FLAG = --testnet-magic 2
submit-testnet: sign-tx ## Submit transaction to preview testnet
	scripts/submit-tx.sh $(NETWORK_FLAG)

submit-mainnet: NETWORK = mainnet
submit-mainnet: NETWORK_FLAG = --mainnet
submit-mainnet: sign-tx ## Submit transaction to mainnet (with confirmation)
	scripts/submit-tx.sh $(NETWORK_FLAG) --confirm

test-lifecycle: ## Run the full test lifecycle
	scripts/test-lifecycle.sh

report: ## Generate a status report
	scripts/generate-report.sh

journal-entry: ## Create a new journal entry
	scripts/journal-entry.sh

clean: ## Remove generated transaction and action files
	rm -f *.action *.raw *.signed tx.*

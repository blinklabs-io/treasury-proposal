# Blink Treasury Proposal - Makefile
# Usage: make [target] [NETWORK=preview|preprod|mainnet]

NETWORK       ?= preview
METADATA_FILE ?= metadata/proposal-metadata.json

.PHONY: help check-prereqs generate-test-keys register-stake fetch-guardrails hash governance-action \
        build-tx sign-tx submit-testnet submit-mainnet test-lifecycle report journal-entry clean

help: ## Show all available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-prereqs: ## Run prerequisite checks
	scripts/check-prereqs.sh

generate-test-keys: ## Generate a fresh wallet for preview testnet
	NETWORK=$(NETWORK) scripts/generate-test-keys.sh

register-stake: ## Register the stake key on-chain (required once)
	NETWORK=$(NETWORK) scripts/register-stake.sh

fetch-guardrails: ## Fetch the on-chain guardrails script
	NETWORK=$(NETWORK) scripts/fetch-guardrails.sh

hash: ## Hash the proposal metadata JSON
	scripts/hash-metadata.sh $(METADATA_FILE)

governance-action: hash ## Create the governance action (depends on hash)
	NETWORK=$(NETWORK) scripts/create-governance-action.sh

build-tx: governance-action ## Build the transaction (depends on governance-action)
	NETWORK=$(NETWORK) scripts/build-tx.sh

sign-tx: build-tx ## Sign the transaction (depends on build-tx)
	NETWORK=$(NETWORK) scripts/sign-tx.sh

submit-testnet: NETWORK = preview
submit-testnet: sign-tx ## Submit transaction to preview testnet
	NETWORK=$(NETWORK) scripts/submit-tx.sh

submit-mainnet: NETWORK = mainnet
submit-mainnet: sign-tx ## Submit transaction to mainnet (with confirmation)
	NETWORK=$(NETWORK) scripts/submit-tx.sh --confirm

test-lifecycle: ## Run the full test lifecycle
	NETWORK=$(NETWORK) METADATA_FILE=$(METADATA_FILE) scripts/test-lifecycle.sh

report: ## Generate a status report
	scripts/generate-report.sh

journal-entry: ## Create a new journal entry
	scripts/journal-entry.sh

clean: ## Remove generated transaction and action files
	rm -f *.action *.raw *.signed tx.* stake-reg.* keys/stake-reg.cert scripts/guardrails.plutus

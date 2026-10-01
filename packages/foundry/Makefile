PHONY: build deploy deploy-and-generate-abis generate-abis get-address account chain fork compile flatten format lint test verify

DEPLOY_SCRIPT ?= script/Deploy.s.sol

# Start a plain local Anvil chain (no fork)
chain:
	anvil

fork:
	@FORK_URL=$${FORK_URL:-$${HEDERA_RPC_URL:-https://testnet.hashio.io/api}}; \
	echo "Starting Anvil fork against $$FORK_URL with chain-id 296..."; \
	anvil --fork-url $$FORK_URL --chain-id 296

# Deploy the contracts
deploy:
	@if [ ! -f "$(DEPLOY_SCRIPT)" ]; then \
		echo "Error: Deploy script '$(DEPLOY_SCRIPT)' not found"; \
		exit 1; \
	fi
	@mkdir -p deployments
	@if [ "$(RPC_URL)" = "localhost" ]; then \
		rm -rf broadcast/Deploy.s.sol/31337; \
		forge script $(DEPLOY_SCRIPT) --rpc-url localhost --unlocked --sender $${LOCALHOST_SENDER:-0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266} --broadcast --ffi; \
	elif [ "$(RPC_URL)" = "hedera_testnet" ]; then \
		forge script $(DEPLOY_SCRIPT) --rpc-url https://testnet.hashio.io/api --account $(ETH_KEYSTORE_ACCOUNT) --broadcast --ffi --slow --legacy; \
	elif [ "$(RPC_URL)" = "hedera_mainnet" ]; then \
		forge script $(DEPLOY_SCRIPT) --rpc-url https://mainnet.hashio.io/api --account $(ETH_KEYSTORE_ACCOUNT) --broadcast --ffi --slow --legacy; \
	else \
		forge script $(DEPLOY_SCRIPT) --rpc-url $(RPC_URL) --account $(ETH_KEYSTORE_ACCOUNT) --broadcast --ffi --slow; \
	fi

# Deploy and generate ABIs (used by scripts-js/parseArgs.js)
deploy-and-generate-abis: deploy generate-abis

# Generate TypeScript ABIs for the Next.js frontend
generate-abis:
	node scripts-js/generateTsAbis.js

# List account
account:
	@node scripts-js/checkAccountBalance.js

# Get address of a keystore
get-address:
	@cast wallet address --account $(ACCOUNT_NAME)

# Compile contracts
compile:
	forge compile

# Flatten contracts
flatten:
	forge flatten

# Format code
format:
	forge fmt && prettier --write ./scripts-js/**/*.js

# Lint code
lint:
	forge fmt --check && prettier --check ./scripts-js/**/*.js

# Run tests
test:
	forge test

# Verify contracts on Sourcify (Hedera is now supported on the main Sourcify instance)
# Usage: make verify CONTRACT=0xAddress CONTRACT_PATH=contracts/MyContract.sol:MyContract CHAIN_ID=296
# See: https://hedera.com/blog/smart-contract-verification-sourcify-dev-now-supported
verify:
	@if [ -z "$(CONTRACT)" ] || [ -z "$(CONTRACT_PATH)" ]; then \
		echo "Usage: make verify CONTRACT=0xAddress CONTRACT_PATH=contracts/MyContract.sol:MyContract CHAIN_ID=296"; \
		echo ""; \
		echo "Or use yarn commands:"; \
		echo "  yarn verify:testnet 0xAddress contracts/MyContract.sol:MyContract"; \
		echo "  yarn verify:mainnet 0xAddress contracts/MyContract.sol:MyContract"; \
		exit 1; \
	fi
	forge verify-contract $(CONTRACT) $(CONTRACT_PATH) --chain-id $(CHAIN_ID) --verifier sourcify

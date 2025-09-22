-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil

# Default Anvil keys & addresses
DEFAULT_ANVIL_KEY     := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEFAULT_ANVIL_KEY_2   := 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
DEFAULT_ANVIL_ADDRESS := 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
DEFAULT_ANVIL_ADDRESS_2 := 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
# make deploy NETWORK=base-sepolia
# make deploy NETWORK=mainnet
# Default to local node unless ARGS specifies a network
ifeq ($(NETWORK),mainnet)
    NETWORK_ARGS := --rpc-url $(BASE_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
else ifeq ($(NETWORK),base-sepolia)
    NETWORK_ARGS := --rpc-url $(BASE_SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
else
    NETWORK_ARGS := --rpc-url http://127.0.0.1:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast
endif

# Build contracts
build:
	forge build

# Run tests
test:
	forge test -vvv

# Deploy using selected network args
deploy:
	@forge script script/DeployOnScriptUserManagement.s.sol:DeployOnScriptUserManagement $(NETWORK_ARGS)

# Start local anvil node
anvil:
	anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

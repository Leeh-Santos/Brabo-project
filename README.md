# Brabo Protocol

A DeFi ecosystem on Base Mainnet pairing an ERC-20 token with automated buybacks, protocol-owned liquidity, dynamic NFT tiers, and fixed-rate staking with NFT-boosted APR.

**Live frontends:** [brabomarkets.com](https://brabomarkets.com) · [brabostaking.com](https://brabostaking.com)

> ⚠️ **Disclaimer.** This is an unaudited DeFi protocol. Smart contracts handle real value and carry real risk. Use at your own discretion and review the code before interacting on mainnet.

---

## What is Brabo?

Brabo is a small-cap DeFi protocol built around a single thesis: a token only matters if its surrounding mechanics actually move value back to holders. The protocol bundles three pieces that talk to each other on-chain:

1. **Brabo Markets** — the ERC-20 token, a Uniswap V3 buyback engine, and a dynamic NFT tier system.
2. **Brabo Staking** — fixed-rate staking with NFT-tiered APR boosts and time-weighted reward accrual.
3. **NftBrabo** — on-chain SVG NFTs (Bronze / Silver / Gold) that act as the cross-protocol boost layer.

Every ETH that flows in through the buyback path is split **80/20** — 80% added to protocol-owned liquidity on Uniswap V3, 20% used to buy back BRB. Holders who stake earn a fixed APR; NFT holders earn more.

---

## Architecture

```
                       [TOKEN CONTRACT]
                       10M Total Supply
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
      [FUNDME]            [STAKING]           [UNISWAP V3 LP]
      8M tokens           1M tokens           500k + ETH seed
          │                   │                   │
       Fund &              Stake &             Buy/Sell
     get tokens          earn rewards         on the pool
          │                   │                   │
          └───────────────────┼───────────────────┘
                              │
                       [NFT BONUSES]
                    Bronze / Silver / Gold
                       +2% / +5% / +10%
```

### Tokenomics (10M total supply)

| Allocation       | Amount  | Purpose                             |
| ---------------- | ------- | ----------------------------------- |
| FundMe reserve   | 8M (80%)| User entry path, supports growth    |
| Staking rewards  | 1M (10%)| ~2 year emission schedule           |
| Initial LP       | 500k (5%)| Seeded with ETH on Uniswap V3      |
| Team             | 300k (3%)| 3-year vest                        |
| Marketing        | 200k (2%)| Growth and operations              |

### NFT tiers

| Tier   | APR Boost |
| ------ | --------- |
| Bronze | +2%       |
| Silver | +5%       |
| Gold   | +10%      |

NFTs are minted as dynamic ERC-721s with on-chain SVG metadata and act as multiplicative boosts on the staking contract's base APR.

---

## Repository layout

```
.
├── .github/workflows/      # CI: forge build + test on push/PR
├── foundry-Fundme/         # Foundry project root
│   ├── src/
│   │   ├── BraboMarkets.sol    # ERC-20 + Uniswap V3 buyback + NFT mint logic
│   │   ├── StakingBrabo.sol    # Fixed-APR staking with NFT boosts
│   │   ├── NftBrabo.sol        # Dynamic on-chain SVG ERC-721
│   │   └── PriceConverter.sol  # Chainlink ETH/USD price feed library
│   ├── test/               # Unit + fork tests
│   ├── script/             # Deployment scripts
│   └── foundry.toml
├── .gitmodules             # Foundry deps (forge-std, OZ, Chainlink, Uniswap V3)
├── IMPORTANT.TXT           # Working notes
└── TODO.txt                # Roadmap / scratchpad
```

---

## Tech stack

- **Solidity** `0.8.28`
- **Foundry** (forge / cast / anvil) for build, test, and deployment
- **OpenZeppelin Contracts** — ERC-20, ERC-721, access control
- **Chainlink** — ETH/USD price feed (`AggregatorV3Interface`)
- **Uniswap V3** — `ISwapRouter`, `INonfungiblePositionManager`, `TickMath`, `TransferHelper`
- **WETH** wrapping via Uniswap V2 periphery interface
- **Base Mainnet** for production deployment

---

## Getting started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- A Base RPC URL (Alchemy, Infura, or public)
- An EVM wallet private key for deployment (use a fresh one — **never** commit it)

### Clone and build

```bash
git clone --recurse-submodules https://github.com/Leeh-Santos/Brabo-project.git
cd Brabo-project/foundry-Fundme
forge build
```

If you forgot `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

### Environment

Create a `.env` in `foundry-Fundme/`:

```bash
BASE_RPC_URL=https://mainnet.base.org
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
PRIVATE_KEY=0x...
ETHERSCAN_API_KEY=...
```

Then load it: `source .env`

---

## Testing

The test suite is split into **unit tests** (fast, mocked) and **fork tests** (run against a Base mainnet fork to exercise real Uniswap V3 / Chainlink integration).

```bash
# Full suite
forge test

# Verbose output
forge test -vvv

# Single test
forge test --match-test testStakeWithNftBoost -vvv

# Fork tests only
forge test --fork-url $BASE_RPC_URL --match-contract Fork

# Coverage
forge coverage
```

CI runs on every push and PR via GitHub Actions (`.github/workflows/`).

---

## Deployment

Scripts live in `foundry-Fundme/script/`. Order matters: deploy the NFT first, then the token (which references the NFT for tier checks), then staking.

```bash
# Dry run
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL

# Live deploy + verify
forge script script/Deploy.s.sol \
  --rpc-url $BASE_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

After deployment, the token contract seeds the Uniswap V3 pool with 500k BRB + ETH and the staking contract is funded with its 1M BRB allocation.

---

## Security notes

This protocol is **unaudited**. Known design considerations baked into the contracts:

- Uniswap V3 swaps use slippage protection via `amountOutMinimum` and explicit deadlines
- Token ordering for the BRB/WETH pool is checked at deploy time
- Chainlink price feeds are used for USD conversion with staleness checks
- Staking uses lazy reward accrual (Synthetix-style reward-per-token accumulator) to avoid unbounded gas in reward updates
- `_calculatePendingRewards` is view-only; reward state is only mutated on stake/unstake/claim

If you find an issue, please open a GitHub issue or contact the maintainer directly. **Do not** disclose vulnerabilities publicly before they're patched.

---

## Live deployments (Base Mainnet)

Verified contracts and addresses are listed on [brabomarkets.com](https://brabomarkets.com) and [brabostaking.com](https://brabostaking.com). Always verify you're interacting with the official addresses before approving spend.

---

## License

MIT — see [LICENSE](./LICENSE) (add one if it's not there yet).

---

## Author

Built by [@Leeh-Santos](https://github.com/Leeh-Santos) — smart contract developer based in Lisbon. Find more work at [github.com/Leeh-Santos](https://github.com/Leeh-Santos).
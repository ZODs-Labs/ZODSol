# RFC: Multi-chain EVM token prices in the menu-bar ticker

Status: Implemented (2026-07-05)
Author: solution-architect pass
Date: 2026-07-05
Scope: add "paste any EVM token contract, see its live USD price in the menu bar" to the existing ticker, with automatic chain detection.

Implementation note: the `HeliusProvider` target was renamed to `DataProviders` and reorganized into peer source folders (`Helius/`, `Jupiter/`, `CEX/`, `EVM/`, `Ticker/`, `Shared/`), since it already housed Kraken, Coinbase and Jupiter under a Helius-named target. Still eight SwiftPM targets, no new target. EVM value types and ports live in `SolanaKit`, the `TokenPasteResolver` facade in `WalletOverviewDomain`, the keyless clients in `DataProviders/EVM/`, wired at `StatusItemController` (resolver) with the price adapter folded into `LayeredTickerPriceProvider`.

---

## 1. Problem statement

The menu-bar ticker prices two things today: curated CEX blue-chips (SOL, BTC, ETH via Kraken/Coinbase) and arbitrary Solana mints (via Jupiter). A user cannot paste an Ethereum, Base, BSC or other EVM token contract and track its price.

We want: paste any EVM token address, the app figures out which chain it lives on by itself, resolves the token, shows a live USD price and re-fetches it on the existing cadence. No API keys, no chain picker up front, no wallet connection.

## 2. Goals and non-goals

Goals
- Paste a bare `0x` contract address; the app detects the chain automatically and prices it.
- Keyless, no signup, no PII, dedicated credential-free session (same invariant the ticker already holds).
- Slot into the existing source-agnostic ticker seam with the smallest clean surface. No new SwiftPM target. No spaghetti.
- Production-grade handling of the full edge-case matrix (section 9): never crash, never show silently-wrong data, always a clear message.

Non-goals (v1)
- EVM balances, wallet tracking, sends, swaps, approvals. This is price display only.
- ENS resolution (needs an EVM RPC, breaks the keyless budget).
- EIP-55 checksum validation and checksummed logo URLs (needs keccak256, which Apple frameworks do not provide and the repo bans deps; see ADR-7).
- TWAP / multi-source price aggregation. A menu-bar ticker shows a spot read with trust gates, not an oracle.
- Runtime risk badges in the bar (low-liquidity/off-peg pills). Trust signals surface at add-time; runtime badges are a fast-follow (section 11).

## 3. Top quality attributes (forced ranking)

At this scale latency, throughput and cost are non-constraints: at most `TickerSettingsStore.maxEntries` tokens, roughly one request per 10 s, keyless (`$0`). So the ranking that drives every decision below is:

1. Correctness. This is a wallet; a wrong token on the wrong chain, or a spoofed-stablecoin-as-$1 price, destroys trust. Fail closed on ambiguity.
2. Evolvability / simplicity. The user explicitly asked for a clean abstraction that fits the existing grain. Fewest new moving parts that satisfy 1 and 3.
3. UX smoothness under partial failure. Paste-and-it-works; graceful degradation (the engine already does stale-while-revalidate); a clear message on every edge.

## 4. Constraints (from AGENTS.md / CLAUDE.md / memory)

- Keyless only (pseudonymity). No API key, no account. Dedicated credential-free `URLSession`, never the Helius-key session.
- No new SwiftPM target. Respect the one-directional layering: `ZODSol -> WalletOverviewUI -> {Formatters, WalletOverviewDomain -> {Caching, KeychainKit, SolanaKit, SolanaRPC}}`, `DataProviders -> {SolanaRPC, SolanaKit, KeychainKit}`.
- Persist only the user's token selection plus last-known public prices. No balances, no user addresses, no key material.
- Swift 6.2, strict concurrency, `Sendable`, `any` existentials, actors for shared mutable state.
- Style: 4-space indent, 120 width, no em dashes, no Oxford commas, minimal comments, Apple frameworks only.
- No background fetching carve-out already covers the ticker; EVM hosts join the existing keyless-market-data allow-list.

## 5. Current state (what we reuse unchanged)

The ticker seam is already source-agnostic and identity-blind, so most of the machine needs zero change:

- `PriceTickerEngine` (actor): builds `TickerQuoteRequest(source, identifier)` per entry, does SWR, staleness (`fresh/stale/unavailable`), adaptive cadence, `Retry-After`-honoring backoff, cold-start seeding and persistence. Everything is keyed by the opaque `sourceIdentifier` string. No change.
- `LastKnownPricesStore`, `TickerSettingsStore` (actors): keyed by `sourceIdentifier`, dedup + `maxEntries` cap. No change.
- `TickerSnapshot` / `TickerSegment`: render model. No change for v1 (badges are fast-follow).
- `LayeredTickerPriceProvider` (`TickerQuoteProviding`): groups requests by `source`, fans out concurrently, merges into one keyed-by-identifier outcome. We add one branch.
- `TickerPriceFormatter`: already documents DexScreener-style subscript-zero notation for deep-sub-cent values. Reuse as-is; verify large-price truncation.
- `TickerCustomTokensSection` + `TickerSettingsViewModel`: the paste UI. We extend the paste path and add a chain-disambiguation surface.

The two exact injection points:
- `MenuBarTickerController` builds `LayeredTickerPriceProvider(session: credentialFree, ...)` - add the EVM price client here.
- `StatusItemController` injects the paste resolver into `TickerSettingsViewModel` - add the EVM resolver here.

## 6. Proposed design

### 6.1 The one insight that shapes everything

An EVM contract address does not encode its chain (verified against EIP-1014/CREATE2 derivation and EIP-55). The same `0x` address can be a different token on Ethereum vs BSC, and popular tokens are often deployed at the same address on many chains (CREATE2/CREATE3/LayerZero OFT) - but not universally (Circle issues native USDC at distinct per-chain addresses). Therefore:

> Chain is discovered, never parsed. We learn it by asking a cross-chain indexer which chains actually host a liquid market for that address, then resolving ambiguity by liquidity.

Mainstream wallets (MetaMask, Rabby, Rainbow, Trust) dodge this by making the user select a network first; the token is imported onto the active network. We deliberately do not, because a Solana-native app has no active EVM network. We adopt the aggregator / DexScreener / Phantom "paste-and-resolve" pattern instead - which is exactly the "paste anything, it just works" experience requested.

### 6.2 Data sources (all keyless, live-verified)

| Role | Source | Endpoint | Why |
|---|---|---|---|
| Chain detection + resolve (one-shot, add-time) | DexScreener | `GET /latest/dex/search?q={address}` | Only keyless call that spans all chains and returns `chainId` + `priceUsd` + `priceChange.h24` + `liquidity.usd` together. 300 req/min. |
| Price refresh (primary) | DexScreener | `GET /tokens/v1/{chainId}/{addresses}` | Chain-scoped batch, price + 24h change + liquidity inline, best long-tail freshness. One call per active chain per tick. |
| Price refresh (fallback) + confidence cross-check | DefiLlama | `GET /prices/current/{chain:addr,...}` and `/percentage/{...}?period=24h` | One mixed-chain call, carries a `confidence` field (drop `< 0.8`). Covers DexScreener outage and any token it returns empty for. |

Rejected: CoinGecko (key + 10k/month cap), Moralis, Alchemy, 1inch (all require a key/signup). GeckoTerminal is a viable tertiary but its 30 req/min keyless cap throttles fast; keep it out of v1.

Single-vendor-primary (DexScreener for both detect and refresh) is chosen over DefiLlama-primary because at less-than-ten tokens request minimization is irrelevant, and one vendor means one chain-slug vocabulary and one data shape on the hot path, with 24h change inline (no second call). This mirrors the existing Kraken-primary / Coinbase-fallback layering exactly.

### 6.3 Chain-detection algorithm (the smart part)

```
resolve(address):
  addr = lowercase(trim(address))              # never trust case; addresses are case-insensitive by value
  pairs = DexScreener /latest/dex/search?q=addr
  pairs = pairs.filter { baseToken.address.lowercased() == addr }   # MANDATORY: token must be the BASE, not a quote
  groups = pairs.groupBy(chainId).filter { chainId in supportedChains }
  perChain = groups.map { chain -> (chain, sumLiquidityUSD, deepestPool, symbol, name, imageUrl) }
  qualifying = perChain.filter { sumLiquidityUSD >= liquidityFloor }
  switch qualifying.count:
    0 -> .notFound            (or .unsupportedChain(name) if it resolved only on a non-allow-listed chain)
    1 -> .resolved(chain)     (auto-add silently; the common case for well-known tokens)
    N -> .multipleChains(candidates sorted by liquidity desc)   # user picks; never guess "Ethereum wins"
```

Two non-obvious rules the research proved are mandatory:
- Filter to pairs whose `baseToken.address == query`. A search for canonical Ethereum USDC returned 29 PulseChain pairs and 1 Ethereum pair; `result[0].chainId` is wrong. Group and weight by liquidity.
- The wrapped-native predeploy `0x4200...0006` returns Base, Optimism, Soneium and World Chain at once. Identity is always `(chain, address)`, never address alone.

### 6.4 Identity and persistence

Identity is the tuple `(chain, lowercased-address)`, serialized into the existing opaque `sourceIdentifier`:

```
sourceIdentifier = "evm:" + chain.slug + ":" + lowercasedAddress
                 e.g. "evm:base:0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
```

- The `evm:` prefix plus chain slug makes it self-describing and collision-proof against Solana mints and against the same address on another chain.
- The engine, both stores and the last-known cache already key on `sourceIdentifier`, so persistence and dedup work with zero change. `TickerSettingsStore.addEntry` already dedups by `sourceIdentifier` and enforces the cap.
- Store lowercase, always. Render checksummed only in the UI (deferred, ADR-7).

### 6.5 Abstraction and patterns

We extend the app's existing grain rather than inventing a new one. Named patterns, each already present:

- Adapter, one per price source behind `TickerQuoteProviding`. EVM is a new adapter (`EVMDexPriceClient`) folded into the existing Composite (`LayeredTickerPriceProvider`).
- Strategy, for input family. A pure `PasteClassifier` maps the raw string to `{ evmAddress | solanaMint | explorerURL(extract) | ensName(reject) | unrecognized }`.
- Facade, one entry point for the UI. `TokenPasteResolver` (domain) owns classify -> route -> build-entry and returns a discriminated `PasteResolution`, so the view model becomes trivial.
- Ports and adapters. Protocols live in `SolanaKit` (the shared value-types layer that already holds `TickerPriceSource`, `TickerQuoteProviding`, `TickerTokenResolving`); concrete keyless clients live in `DataProviders` beside `JupiterTokenResolver`.

New types by target:

`SolanaKit` (value types + ports)
```swift
enum TickerPriceSource: String, ... { case kraken, coinbase, jupiter, evmDex }   // + one case

struct EVMChain: Sendable, Hashable, Codable {          // value type, allow-list driven
    let slug: String                 // internal canonical, e.g. "ethereum", "base", "bsc"
    let displayName: String
    let dexScreenerId: String        // "ethereum", "base", "bsc", "avalanche", ...
    let defiLlamaId: String          // "ethereum", "base", "bsc", "avax", ...
    let nativeSymbol: String         // "ETH", "BNB", "POL", "AVAX"
    static let supported: [EVMChain] // Tier-1 allow-list (section 7)
}

struct EVMTokenRef: Sendable, Hashable {                // (chain, lowercased address)
    let chain: EVMChain
    let address: String              // lowercased
    var sourceIdentifier: String { "evm:\(chain.slug):\(address)" }
    init?(sourceIdentifier: String)  // failable parse
}

enum EVMResolution: Sendable {
    case resolved(EVMResolvedToken)                 // one qualifying chain
    case multipleChains([EVMResolvedToken])         // user disambiguates
    case notFound
    case unsupportedChain(String)                   // named, for a clear message
    case lowLiquidity(usd: Decimal)
}

protocol EVMTokenResolving: Sendable {              // implemented in DataProviders
    func resolve(address: String) async -> EVMResolution
}
```

`WalletOverviewDomain` (orchestration)
```swift
enum PasteResolution: Sendable {
    case resolved(TickerEntry)                 // ready to add
    case needsChainChoice([TickerEntry])       // one entry per candidate chain, ranked by liquidity
    case rejected(reason: String)              // user-facing message
}

struct TokenPasteResolver: Sendable {          // the Facade
    let solana: any TickerTokenResolving        // existing Jupiter resolver
    let evm: any EVMTokenResolving              // new
    func resolve(_ raw: String) async -> PasteResolution
}

extension TickerCatalog {
    static func evmEntry(_ token: EVMResolvedToken) -> TickerEntry   // source: .evmDex
}
```

`DataProviders` (keyless clients, same credential-free session)
```swift
struct EVMDexResolverClient: EVMTokenResolving { ... }     // DexScreener /latest/dex/search + filter/group/floor
// LayeredTickerPriceProvider gains an evmDex branch:
//   filter requests by .evmDex, parse EVMTokenRef, group by chain,
//   batch /tokens/v1/{chain}/{addrs}, pick deepest pool per token,
//   fall back to DefiLlama for empties, map to PriceQuote keyed by full sourceIdentifier.
struct DexScreenerEndpoint { ... }   // added to Endpoints.swift
struct DefiLlamaEndpoint { ... }
```

The view model change is small: `addPasted(_ raw:)` calls the facade and switches on `PasteResolution` - `.resolved` appends, `.needsChainChoice` drives a compact inline picker, `.rejected` sets `addError`. The existing `addPastedMint` Solana path is absorbed by the facade.

## 7. Supported chains (v1 allow-list)

Tier 1, by 2026 liquidity. The per-vendor slug table is the load-bearing data; a missing entry is a silent empty result, so a completeness test guards it (section 10).

| Chain | internal slug | DexScreener id | DefiLlama id | native |
|---|---|---|---|---|
| Ethereum | ethereum | ethereum | ethereum | ETH |
| Base | base | base | base | ETH |
| Arbitrum | arbitrum | arbitrum | arbitrum | ETH |
| Optimism | optimism | optimism | optimism | ETH |
| Polygon | polygon | polygon | polygon | POL |
| BNB Chain | bsc | bsc | bsc | BNB |
| Avalanche | avalanche | avalanche | avax | AVAX |

A token that resolves only on a chain outside this set is rejected with a named message ("This token is on Linea, which is not supported yet."). Expanding the list is pure data plus a test row, a two-way door.

## 8. Data flow

Add
```
paste -> classify
  0x[40 hex]         -> EVM: DexScreener search -> filter(baseToken==addr) -> group by supported chain
                        -> liquidity floor -> {0 notFound | 1 auto | N picker}
                        -> TickerEntry(source:.evmDex, id:"evm:base:0x..", symbol,name,decimals,iconURL)
                        -> TickerSettingsStore.addEntry (dedup + cap) -> engine.configure
  base58 mint        -> existing Solana/Jupiter path
  explorer URL       -> extract first 0x[40], seed chain hint from host, then EVM path
  ENS / unrecognized -> rejected(reason)
```

Refresh (unchanged engine)
```
engine -> TickerQuoteRequest(.evmDex, "evm:base:0x..")
       -> LayeredTickerPriceProvider groups .evmDex by chain
       -> EVMDexPriceClient: /tokens/v1/{chain}/{addrs} -> deepest pool per token -> priceUsd + change24h
          (fallback DefiLlama /prices/current + /percentage; drop confidence < 0.8)
       -> PriceQuote keyed by full sourceIdentifier -> merged outcome
       -> engine SWR / staleness / backoff / persist  (all existing)
```

## 9. Edge-case matrix (production handling)

Grouped; every row is "never crash, never silently-wrong, always a clear state". Full catalog verified in research; highlights:

Input
- Whitespace / case: trim, validate `^0x[0-9a-fA-F]{40}$`, lowercase for API and key.
- Mixed-case (EIP-55): do not hard-block on checksum (we cannot compute keccak256, ADR-7); the indexer returning empty is the real validity gate.
- Explorer URL pasted: extract first `0x[40]`; if the host names a chain (basescan) seed it as the disambiguation hint.
- Solana mint pasted into EVM flow: detect base58, steer to the existing Jupiter path transparently ("That is a Solana token, adding via Jupiter").
- ENS name: reject cleanly ("ENS is not supported, paste the 0x contract address"). No hidden RPC.

Resolution / chain
- Same address, different tokens per chain: multiple qualifying groups -> chain picker, ranked by liquidity, never auto-pick.
- Same token, same address, many chains (OFT/CREATE2): default to deepest-liquidity chain, offer the others.
- USDC-style distinct per-chain address: resolve strictly by the pasted address; do not equate by symbol.
- EOA / NFT / non-ERC20 / no pool: empty pairs across all chains -> "No tradable token found at this address." Never add a blank entry.
- Chain not supported: name it in the message.

Price quality / trust
- Deepest pool only (max `liquidity.usd`); never `pairs[0]`; consume the source's precomputed `priceUsd` (already USD- and decimals-normalized); never native x assumed-quote-USD; never USDC=$1.
- Liquidity floor at add-time (configurable, e.g. $10k): below it, refuse with the number ("Not enough liquidity for a reliable price ($X).").
- Spoofed stablecoin: a tiny canonical `(chain, symbol) -> address` allow-list; a pasted address claiming a reserved symbol at a non-canonical address is added but flagged "Unverified - symbol matches USDC but this is not the official contract" at add-time.
- Bad tick: reject non-finite / zero / negative at ingestion (treat as a miss, do not overwrite last-known). Optional outlier clamp on thin-liquidity entries (hold last-known if the jump exceeds a large band).
- Stablecoin depeg: show the real number, never clamp to $1.
- Honeypot / fee-on-transfer / rebasing: unit price is still valid, display it; the ticker does no quantity math so there is nothing to get wrong. Surface a "fee-on-transfer" tag only if the source flags it.

Lifecycle / failure
- Rugged after add: keep the entry (their selection is not data-loss), grow staleness, then "Price unavailable - liquidity gone" with dimmed last-known and a timestamp. Removal is user-initiated.
- 429: honor `Retry-After` (engine already threads it), keep last-known with the stale badge, one batched request per tick, single in-flight.
- Primary outage: fall back to DefiLlama per the layered provider; else last-known + exponential backoff (already implemented).
- Offline / asleep / locked: the engine already gates the loop off and seeds last-known on cold start.

Display
- Sub-cent and huge prices: reuse `TickerPriceFormatter` (subscript-zero already documented); verify large-value truncation with full value in the expanded view.
- Hostile metadata: sanitize and hard-truncate symbol (<=10 chars, strip control/RTL/zero-width unicode); fall back to a short address when symbol is empty; https-only icon URLs.
- Cap reached: block with "Ticker is full (max N). Remove one to add another." Show the count in settings.
- Duplicate: dedup on `(chain, lowercased-address)`; highlight the existing row ("Already in your ticker").

## 10. Testing

Per repo rules: pure logic first, fixtures through `MockURLProtocol`, no live Helius/Jupiter/DexScreener calls.

- Resolution: fixture the USDC "29 PulseChain + 1 Ethereum" search; assert we pick Ethereum by liquidity group, not `result[0]`. Fixture a same-address-two-chains case; assert `.multipleChains`. Fixture EOA/NFT empties; assert `.notFound`.
- Identity: round-trip `EVMTokenRef <-> sourceIdentifier`; assert lowercase normalization; assert `0x4200...0006` scopes by chain.
- Chain map completeness: for every `EVMChain.supported`, assert `dexScreenerId` and `defiLlamaId` are non-empty (a missing slug is silent at runtime).
- Trust gates: liquidity floor, spoofed-USDC flag, non-finite/zero/negative rejection, outlier clamp.
- Classifier: 0x / base58 / explorer URL / ENS / whitespace / mixed-case table.
- Provider: `LayeredTickerPriceProvider` merges evmDex quotes keyed by full identifier; DefiLlama fallback on DexScreener empty; `shouldBackOff` on 429.

## 11. Rollout, reversibility, open questions

- Additive, behind the existing widget master toggle. No migration.
- Two-way doors: the price vendor sits behind `EVMTokenResolving` / the adapter, swappable. The chain allow-list is data. GeckoTerminal/DefiLlama can be re-weighted freely.
- One-way door to lock now: the `sourceIdentifier` string format `evm:{slug}:{addr}` is persisted schema. Fixed in this RFC; document it. Old builds decoding an `.evmDex` entry fall back to `.seeded` (lossy but graceful) - acceptable for a single-user app, not a blocker.
- Fast-follow (not v1): runtime risk badges in `TickerSegment` (low-liquidity / off-peg / unverified), which need render-model fields; native-coin-by-sentinel pricing via the existing Kraken/Coinbase path.
- Open question for the owner: the disambiguation UX when N chains qualify - inline picker vs. auto-pick-deepest-with-a-switch. Recommendation: inline picker pre-highlighting the deepest, so the common single-chain case stays zero-click and the ambiguous case stays safe.

## 12. ADR summary

- ADR-1 Chain is discovered by cross-chain indexer search, never parsed from the address. Resolve ambiguity by liquidity; fail closed to a picker on N, to a message on 0.
- ADR-2 DexScreener primary for both detection and refresh; DefiLlama fallback + confidence cross-check. Mirrors the existing Kraken/Coinbase layering.
- ADR-3 Canonical price = deepest pool's precomputed `priceUsd`; liquidity floor + non-finite/outlier rejection as proportionate manipulation guards (TWAP out of scope).
- ADR-4 Identity is `(chain, lowercased-address)` serialized as `evm:{slug}:{addr}` into the opaque `sourceIdentifier`; engine and stores unchanged.
- ADR-5 Adapter + Strategy + Facade over the existing Composite seam; ports in SolanaKit, clients in DataProviders; view model stays trivial.
- ADR-6 Allow arbitrary paste by address (never by symbol); gate with a liquidity floor and flag spoofed reserved-symbol tokens, rather than an allowlist-only restriction (which would contradict "paste any EVM token").
- ADR-7 v1 normalizes to lowercase and skips EIP-55 checksum validation and checksummed Trust Wallet logo URLs, because keccak256 is not in Apple frameworks and the repo bans third-party deps. Logos come from the indexer's inline `imageUrl` with a generated placeholder fallback. If checksum support is ever wanted, add a self-contained pure-Swift keccak256 behind golden EIP-55 vectors.

# Solana Support: Migration Plan

## Phase Documents

- [Phase 0: Base58 Encoding](phase-0-base58.md) - Pure Elixir Base58 encode/decode
- [Phase 1: Ed25519 Keys & Signing](phase-1-ed25519.md) - OTP-native Ed25519, keypair management
- [Phase 2: Transaction Building](phase-2-transaction.md) - Message serialization, signing, SystemProgram
- [Phase 3: Solana RPC Client](phase-3-rpc.md) - Typed RPC methods, shared transport extraction

## Key Decisions Made

1. **`Signet.Base58`** lives at top level (not under `Signet.Solana`) - it's a generic encoding like `Signet.Hex`
2. **No external deps for Solana core** - OTP `:crypto` handles Ed25519, Base58 is implemented in-house
3. **Solana Signer GenServer follows same MFA pattern** as Ethereum, but simpler (no recovery bit, no chain ID). Supports local Ed25519 and GCP CloudKMS backends.
4. **Separate `Signet.Solana.Signer.CloudKMS`** module - not shared with Ethereum's KMS signer. Every step differs (request field, PEM parsing, signature format). Small modules, clear separation.
5. **Extract `Signet.RPC.Transport`** - Shared JSON-RPC framing used by both Ethereum and Solana RPC
6. **Binary pubkeys in public API** - Functions accept 32-byte binary pubkeys, encode to Base58 internally for RPC
7. **Default encoding: base64** for RPC data (faster than base58, no size limit)
8. **Default commitment: `:finalized`** for all RPC reads
9. **Legacy transactions first** - Versioned (v0) transactions deferred until needed

---

## Current State of Signet

Signet is a lightweight Ethereum RPC client for Elixir (v1.5.0). Everything is Ethereum-specific and lives directly under the `Signet.*` namespace with no chain-level namespacing.

### Module Inventory

| Module | What It Does | Ethereum-Specific? |
|---|---|---|
| `Signet.RPC` | JSON-RPC client (30+ methods), transaction sending, calling, gas estimation | Yes (methods, error decoding, gas logic) |
| `Signet.Transaction` | Build/encode/sign V1 (legacy) and V2 (EIP-1559) transactions | Yes (RLP, EIP-155, EIP-1559) |
| `Signet.Signer` | GenServer that wraps signing backends, finds recovery bit | Yes (secp256k1, recovery bit, EIP-155 v-value) |
| `Signet.Signer.Curvy` | Private key signing via Curvy (secp256k1) | Yes (secp256k1, keccak digest) |
| `Signet.Signer.CloudKMS` | Google Cloud KMS signing | Yes (secp256k1 key type) |
| `Signet.Recover` | Signature recovery and verification | Yes (secp256k1 recovery, keccak, EIP-191) |
| `Signet.Keys` | Keypair generation | Yes (secp256k1, keccak address derivation) |
| `Signet.Hex` | Hex encoding/decoding, `~h` sigil, EIP-55 checksummed addresses | Mostly (hex is generic, checksummed addresses are Ethereum) |
| `Signet.Hash` | Keccak-256 hashing | Yes (Keccak is Ethereum's hash) |
| `Signet.Util` | Wei conversion, chain IDs, address derivation, padding | Mostly Ethereum |
| `Signet.Typed` | EIP-712 typed data encoding | Yes |
| `Signet.Block` | Block deserialization | Yes |
| `Signet.Receipt` | Transaction receipt deserialization | Yes |
| `Signet.Trace` / `TraceCall` / `DebugTrace` | Trace deserialization | Yes |
| `Signet.FeeHistory` | EIP-1559 fee history | Yes |
| `Signet.Filter` | Event log filtering via `eth_newFilter` | Yes |
| `Signet.Erc20` | ERC-20 token wrapper | Yes |
| `Signet.Assembly` / `Signet.VM` | EVM assembler and pure VM | Yes |
| `Signet.OpenChain` | 4byte signature lookup | Yes |
| `Signet.Sleuth` | Contract call helper | Yes |
| `Signet.Application` | Supervision tree, config | Partially (starts signers, Finch) |
| `Mix.Signet.Gen` | ABI code generation | Yes |

### Key Dependencies

- `curvy` - secp256k1 signing (Ethereum's curve)
- `ex_sha3` - Keccak-256
- `ex_rlp` - RLP encoding (Ethereum serialization)
- `abi` - Solidity ABI encoding/decoding
- `jason` - JSON (generic)
- `finch` - HTTP client (generic)

### Architecture Patterns Worth Noting

1. **Signer GenServer pattern**: `Signet.Signer` is a GenServer that delegates to an `{mod, fun, args}` triple. The signing backend (Curvy, CloudKMS) returns a `%Curvy.Signature{}` struct, and the Signer wraps it with recovery bit logic and EIP-155 encoding. This is tightly coupled to Ethereum's secp256k1 + recovery bit model.

2. **RPC module**: A single large module (~1700 lines) that handles JSON-RPC communication, transaction building, gas estimation, and response deserialization. The JSON-RPC transport itself is generic, but every method and response parser is Ethereum-specific.

3. **Config-driven**: Node URL, chain ID, and signers are configured via `Application.get_env(:signet, ...)`.

4. **Deserialization pattern**: Modules like `Block`, `Receipt`, `Trace` each have a `deserialize/1` function that takes a JSON-RPC response map and returns a typed struct.

---

## What Solana Needs

### Cryptography: Ed25519

Solana uses **Ed25519** (not secp256k1). Key differences:

| | Ethereum (secp256k1) | Solana (Ed25519) |
|---|---|---|
| Curve | secp256k1 (ECDSA) | Ed25519 (EdDSA) |
| Public key | 64 bytes uncompressed, derived via keccak → last 20 bytes = address | 32 bytes = the address itself |
| Private key | 32 bytes | 32-byte seed (often stored as 64 bytes: seed + pubkey) |
| Signature | 65 bytes (r: 32, s: 32, v: 1) with recovery bit | 64 bytes (R: 32, S: 32), no recovery bit |
| Hashing | Keccak-256 (external to signing) | SHA-512 (internal to Ed25519, no separate digest step) |
| Recovery | Can recover pubkey from signature + message | No recovery possible - must know pubkey |
| OTP support | Via `curvy` library (`:crypto` supports secp256k1 but Curvy is used) | Native `:crypto.sign(:eddsa, :none, msg, [priv, :ed25519])` since OTP 24 |

**Good news**: OTP natively supports Ed25519 via `:crypto` and `:public_key`. No external dependency needed.

```elixir
# Key generation
{pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
# pub = 32 bytes, priv = 64 bytes (seed ++ pub)

# Signing (note: :none for digest, Ed25519 handles internally)
signature = :crypto.sign(:eddsa, :none, message, [priv, :ed25519])
# signature = 64 bytes

# Verification
:crypto.verify(:eddsa, :none, message, signature, [pub, :ed25519])
# => true | false
```

### Encoding: Base58

Solana uses **Base58 (Bitcoin alphabet)** for addresses and transaction signatures. This is plain Base58, NOT Base58Check (no checksum bytes).

- Addresses: 32 bytes → 32-44 character Base58 string
- Signatures: 64 bytes → 87-88 character Base58 string
- Account data in RPC: Can also be base64 or base64+zstd

Options:
1. Use an existing hex package (`b58` / `basefiftyeight`, or `base58`)
2. Implement inline (~30 lines for encode + decode)

Recommendation: Implement it ourselves. The algorithm is trivial (repeated divmod by 58) and avoids a dependency for something so small. We can put it in `Signet.Solana.Base58` or `Signet.Base58`.

### RPC: Solana JSON-RPC

Solana also uses JSON-RPC 2.0, so the transport layer is the same. Key differences:

| Aspect | Ethereum | Solana |
|---|---|---|
| Block concept | Blocks with numbers | Slots (and blocks within slots) |
| Transaction ID | Keccak hash of signed tx | First signature (base58) |
| Nonce | Sequential per-account counter | Recent blockhash (expires ~60-90s) |
| Gas | Gas limit + gas price / EIP-1559 fees | Compute units + priority fees (simpler) |
| Commitment | `latest`, `safe`, `finalized` | `processed`, `confirmed`, `finalized` |
| Data encoding | Hex (`0x`-prefixed) | base58, base64, base64+zstd, jsonParsed |
| Response wrapper | Direct result | Often `{context: {slot}, value: ...}` |

#### Core RPC Methods We'd Want First

**Read operations:**
- `getAccountInfo` - Account data, owner, lamports, executable flag
- `getBalance` - SOL balance in lamports
- `getMultipleAccounts` - Batch account fetch
- `getLatestBlockhash` - Required for transaction building
- `getSlot` / `getBlockHeight` - Current position
- `getMinimumBalanceForRentExemption` - For account creation
- `getTransaction` - Full transaction details by signature
- `getSignatureStatuses` - Poll transaction confirmation

**Write operations:**
- `sendTransaction` - Submit signed transaction
- `simulateTransaction` - Dry-run without submitting

**Other useful:**
- `getRecentPrioritizationFees` - For priority fee estimation
- `getHealth` - Node health check
- `getVersion` - Node version
- `getTokenAccountBalance` - SPL token balance
- `getTokenAccountsByOwner` - SPL token accounts

### Transaction Format

Solana transactions are a custom binary format (not RLP, not protobuf):

```
Transaction = {
  signatures: CompactArray<[u8; 64]>,   // Ed25519 signatures
  message: Message
}

Message = {
  header: {
    num_required_signatures: u8,
    num_readonly_signed_accounts: u8,
    num_readonly_unsigned_accounts: u8,
  },
  account_keys: CompactArray<[u8; 32]>,  // Pubkeys, ordered by permission
  recent_blockhash: [u8; 32],
  instructions: CompactArray<CompiledInstruction>,
}

CompiledInstruction = {
  program_id_index: u8,           // Index into account_keys
  accounts: CompactArray<u8>,     // Indices into account_keys
  data: CompactArray<u8>,         // Opaque bytes for the program
}
```

**Compact array encoding** (like Bitcoin's CompactSize):
- `< 0x80`: 1 byte
- `< 0x4000`: 2 bytes (7-bit little-endian with continuation bit)
- `< 0x200000`: 3 bytes

Key: the **message bytes** are what gets signed directly (no separate hashing step - Ed25519 handles that internally). The first signature also serves as the transaction ID.

There's also **Versioned Transactions (v0)** which add address lookup tables for fitting more accounts, but we can start with legacy format.

### IDL / Borsh (Future)

Solana's equivalent of Ethereum's ABI is the **Anchor IDL** - a JSON description of a program's interface. Instruction data is typically encoded with **Borsh** (Binary Object Representation Serializer for Hashing), not ABI encoding. Non-Anchor programs have no standard IDL.

This is a phase-2 concern. For phase 1, we can construct instruction data manually (raw bytes), which is sufficient for system program interactions (transfers, account creation) and any program where you know the wire format.

---

## Proposed Module Structure

```
lib/signet/
  # Existing Ethereum modules (unchanged for now)
  rpc.ex                    # Signet.RPC (Ethereum)
  transaction.ex            # Signet.Transaction (Ethereum)
  signer.ex                 # Signet.Signer (Ethereum-specific GenServer)
  ...

  # New shared/generic modules
  base58.ex                 # Signet.Base58

  # New Solana modules
  solana/
    rpc.ex                  # Signet.Solana.RPC
    keys.ex                 # Signet.Solana.Keys (Ed25519 keypair generation)
    transaction.ex          # Signet.Solana.Transaction (build, serialize, sign)
    signer.ex               # Signet.Solana.Signer (GenServer, same MFA pattern as Ethereum)
    signer/
      ed25519.ex            # Signet.Solana.Signer.Ed25519 (local key backend)
      cloud_kms.ex          # Signet.Solana.Signer.CloudKMS (GCP KMS Ed25519 backend)
    system_program.ex       # Signet.Solana.SystemProgram (transfer, create account, etc.)
```

Later, we'd consider:
```
  solana/
    token_program.ex        # SPL Token interactions
    borsh.ex                # Borsh serialization
    idl.ex                  # Anchor IDL parsing
    block.ex                # Block/slot deserialization
```

And eventually, namespacing the existing Ethereum modules:
```
  ethereum/
    rpc.ex                  # Signet.Ethereum.RPC (moved from Signet.RPC)
    transaction.ex          # etc.
    ...
```

---

## Implementation Phases

### Phase 1: Foundations

These are the building blocks everything else depends on.

**1a. Base58 encoding/decoding** (`Signet.Base58`)
- Encode binary → Base58 string (Bitcoin alphabet)
- Decode Base58 string → binary
- Handle leading zero bytes (encoded as `1` characters)
- Comprehensive tests with known Solana addresses and signatures

**1b. Ed25519 key management** (`Signet.Solana.Keys`)
- Generate Ed25519 keypairs via `:crypto.generate_key(:eddsa, :ed25519)`
- Import from 64-byte keypair files (Solana CLI format: seed ++ pubkey)
- Import from 32-byte seed
- Derive public key (address) from private key
- Format addresses as Base58 strings
- Tests against known Solana keypairs

**1c. Ed25519 signing** (`Signet.Solana.Signer`, `Signet.Solana.Signer.Ed25519`, `Signet.Solana.Signer.CloudKMS`)
- GenServer signer with MFA backend pattern (same as Ethereum, but simpler)
- Local key backend: sign via OTP `:crypto.sign(:eddsa, :none, ...)`
- CloudKMS backend: sign via GCP KMS `asymmetricSign` with `data` field (raw bytes, not pre-hashed)
- Verify signatures (`:crypto.verify(:eddsa, :none, ...)`)
- Simpler than Ethereum: no recovery bit, no chain ID encoding, no keccak
- Tests against RFC 8032 vectors + mocked KMS

### Phase 2: Transactions

**2a. Compact array encoding** (within `Signet.Solana.Transaction`)
- Encode/decode compact u16 (variable-length integer for array sizes)
- Used throughout transaction serialization

**2b. Transaction building and serialization** (`Signet.Solana.Transaction`)
- Build message struct (header, account keys, recent blockhash, instructions)
- Serialize message to binary (the bytes that get signed)
- Add signatures to create full transaction
- Serialize full transaction for RPC submission
- Deserialize transactions from binary
- Start with legacy format, add v0 (versioned) later

**2c. System program helpers** (`Signet.Solana.SystemProgram`)
- Transfer SOL instruction
- Create account instruction
- These are the most basic operations and good test cases for the transaction builder

### Phase 3: RPC Client

**3a. Core RPC** (`Signet.Solana.RPC`)
- Reuse Finch HTTP client from existing Signet infrastructure
- JSON-RPC 2.0 transport (same as Ethereum, can share `get_body/3` logic)
- Configurable node URL (e.g., `config :signet, :solana_node, "https://api.mainnet-beta.solana.com"`)
- Commitment level support as option on all read methods
- Typed response structs and deserializers (following the same `deserialize/1` pattern)

**3b. Read methods:**
- `get_balance/2` → `{:ok, non_neg_integer()}` (lamports)
- `get_account_info/2` → `{:ok, %AccountInfo{} | nil}`
- `get_multiple_accounts/2` → `{:ok, [%AccountInfo{} | nil]}`
- `get_latest_blockhash/1` → `{:ok, %{blockhash: binary(), last_valid_block_height: non_neg_integer()}}`
- `get_slot/1` → `{:ok, non_neg_integer()}`
- `get_block_height/1` → `{:ok, non_neg_integer()}`
- `get_transaction/2` → `{:ok, %Transaction{} | nil}`
- `get_signature_statuses/2` → `{:ok, [%SignatureStatus{} | nil]}`
- `get_minimum_balance_for_rent_exemption/2` → `{:ok, non_neg_integer()}`

**3c. Write methods:**
- `send_transaction/2` → `{:ok, signature_string}`
- `simulate_transaction/2` → `{:ok, %SimulationResult{}}`

**3d. High-level helpers** (like Ethereum's `execute_trx`):
- `send_and_confirm/2` - Send transaction and poll until confirmed/finalized
- `request_airdrop/2` - Devnet/testnet SOL airdrop (useful for testing)

### Phase 4: Integration & Polish

- Wire up Solana node + signer config in `Signet.Application`
- Documentation and README updates
- Consider the Ethereum namespacing migration (`Signet.RPC` → `Signet.Ethereum.RPC`)

### Phase 4: Tokens (see [phase-4-tokens.md](phase-4-tokens.md))

- PDAs (`Signet.Solana.PDA`) - `find_program_address`
- ATAs (`Signet.Solana.ATA`) - derive addresses, create instructions
- SPL Token Program instructions (`Signet.Solana.TokenProgram`)
- High-level token RPC (`Signet.Solana.Token`) - `get_balance`, `get_all_balances`, `transfer_instructions`
- `~B58` sigil for compile-time Base58 decoding

### Future Phases

- **Sponsored transactions (fee payers)**: Transactions where a third party pays fees on behalf of the user. The signer (user) and fee payer are different accounts. This is critical for onboarding UX and gasless/relayer patterns. Solana natively supports this (fee payer is just the first signer), but we need good ergonomics: building transactions where the user signs but someone else pays, partial signing workflows, and potentially serialization formats for passing partially-signed transactions between parties.
- **Versioned transactions (v0)**: Address lookup tables for fitting more accounts per transaction
- **Borsh serialization**: For Anchor program interaction
- **Anchor IDL parsing**: Code generation from IDL files (like `mix signet.gen` for ABI)
- **WebSocket subscriptions**: `accountSubscribe`, `signatureSubscribe`, etc.

---

## Design Decisions & Open Questions

### 1. Signer Architecture

**Decision: Separate `Signet.Solana.Signer` GenServer, same MFA pattern, simpler internals.**

The Ethereum `Signet.Signer` GenServer is deeply Ethereum-specific (recovery bits, EIP-155, `%Curvy.Signature{}`). Can't be generalized without breaking it. Instead, `Signet.Solana.Signer` follows the same GenServer + MFA backend pattern but is much simpler:

- Backend returns raw `{:ok, <<sig::binary-64>>}` (not `%Curvy.Signature{}`)
- No recovery bit brute-force
- No chain ID encoding
- Caches public key (still useful, especially for KMS to avoid re-fetching)

Two backends:
- `Signet.Solana.Signer.Ed25519` - local key (analogous to `Signet.Signer.Curvy`)
- `Signet.Solana.Signer.CloudKMS` - GCP KMS with `EC_SIGN_ED25519` algorithm (analogous to `Signet.Signer.CloudKMS`, but uses `data` field instead of `digest`, raw 64-byte signatures instead of DER, and Ed25519 PEM parsing instead of EC point extraction)

### 2. RPC Module Sharing

The JSON-RPC transport is identical between Ethereum and Solana. We could extract a shared base.

**Options:**
- **(a)** Copy the HTTP/JSON-RPC plumbing into `Signet.Solana.RPC` (some duplication)
- **(b)** Extract `Signet.RPC.Base` or `Signet.JsonRPC` with shared transport, chain-specific modules call into it

Recommendation: **(b)** Extract the transport. The `send_rpc/3` function, `get_body/3`, HTTP headers, Finch integration, and JSON response parsing are all reusable. Chain-specific modules add their own methods and response parsing.

### 3. Configuration

Currently: `config :signet, :ethereum_node, "..."` and `config :signet, :chain_id, ...`

For Solana: Need `config :signet, :solana_node, "https://api.mainnet-beta.solana.com"` (or devnet/testnet variants).

No chain_id concept in Solana (there's cluster: mainnet-beta, devnet, testnet, but it's identified by the genesis hash, not a numeric ID).

### 4. Base58 Module Location

`Signet.Base58` (top-level, since it's a generic encoding) vs `Signet.Solana.Base58` (namespaced under Solana).

Recommendation: `Signet.Base58` - it's a general-purpose encoding like `Signet.Hex`. Could potentially be useful for Bitcoin or other chains too.

### 5. Hex Package Dependencies

Current Ethereum dependencies that Solana does NOT need:
- `curvy` (secp256k1) - not needed for Ed25519
- `ex_sha3` (keccak) - not needed
- `ex_rlp` (RLP encoding) - not needed
- `abi` (Solidity ABI) - not needed

Solana-specific dependencies:
- None required for phase 1-3! OTP `:crypto` handles Ed25519, and we'll implement Base58 ourselves.
- Eventually might want a Borsh library for Anchor IDL support.

This is nice - Solana support adds zero new dependencies for the core functionality.

---

## Summary

The migration is very feasible. The key insight is that Solana's primitives are simpler than Ethereum's in many ways:

- Ed25519 is natively supported in OTP (no `curvy` equivalent needed)
- No recovery bit complexity
- No RLP encoding
- No ABI encoding (at least for basic operations)
- Transaction format is a straightforward binary protocol
- JSON-RPC transport is identical

The main work is:
1. Base58 encoding (~30 lines + tests)
2. Ed25519 key/signing wrappers (~50 lines + tests)
3. Transaction serialization (~200 lines + tests)
4. RPC client with typed responses (~500 lines + tests, following existing patterns)

The existing Ethereum code stays untouched. New Solana modules live under `Signet.Solana.*`. A shared JSON-RPC transport layer can be extracted from the existing `Signet.RPC` to avoid duplication.

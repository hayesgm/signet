# Phase 4: PDAs, ATAs, and Token Support

**Modules:** `Signet.Solana.PDA`, `Signet.Solana.ATA`, `Signet.Solana.TokenProgram`, `Signet.Solana.Token`
**Dependencies:** Phases 0-3, `:crypto` (SHA-256)
**Adds to:** `Signet.Solana.RPC` (one new method: `get_token_accounts_by_owner`)

---

## Background: How Solana Tokens Work

Solana tokens are fundamentally different from Ethereum's ERC-20 model.

**Ethereum**: A token is a contract. Your balance is a mapping entry inside that contract. Call `USDC.balanceOf(wallet)` and you're done.

**Solana**: Each token balance is a **separate on-chain account** (165 bytes) with its own address. A token account stores:
- `owner` - the wallet that controls it (can transfer from it)
- `mint` - which token this account holds (e.g., USDC's mint address)
- `amount` - the balance

If a wallet holds 5 different tokens, it has 5 separate token accounts. Each has a distinct address.

**Mint**: The Solana equivalent of a token contract address. A mint account defines the token's decimals, total supply, and mint/freeze authorities. USDC on mainnet is `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`.

**Two Token Programs**: The original SPL Token Program and Token-2022 (with extensions like transfer fees, confidential transfers). Both share the same instruction layout for basic operations but have different program IDs. A given mint belongs to one or the other.

---

## Layer 1: Program Derived Addresses (PDAs)

### What

A PDA is an address derived from seeds + a program ID that is guaranteed to NOT have a corresponding private key (not on the Ed25519 curve). Only the owning program can "sign" for a PDA via CPI (cross-program invocation).

PDAs are everywhere in Solana: ATAs, program state accounts, vault accounts, etc.

### Algorithm

```
find_program_address(seeds, program_id):
  for bump = 255 down to 0:
    candidate = SHA-256(seed_1 ++ seed_2 ++ ... ++ [bump] ++ program_id ++ "ProgramDerivedAddress")
    if candidate is NOT a valid Ed25519 public key:
      return {candidate, bump}
  raise "could not find PDA" (extremely unlikely)
```

The "not on curve" check: try to decompress the 32 bytes as an Ed25519 point. If it fails, it's a valid PDA.

### "On Curve" Check (Researched & Validated)

We need to check if 32 bytes represent a valid Ed25519 public key (a point on the curve). **Tested and confirmed:**

- **OTP's `:crypto.verify/5` does NOT work** - it returns `false` for both "valid key + bad sig" and "invalid key". No way to distinguish.
- **Pure math using `:crypto.mod_pow/3` works perfectly** and is fast (C-implemented modular exponentiation).

The algorithm (Ed25519 compressed point decompression check):

```elixir
# Ed25519 field prime and curve constant
p = 2^255 - 19
d = 37095705934669439343138083508754565189542113879843219016388785533085940283555

# Given 32 bytes:
# 1. Decode y: little-endian, clear high bit (sign bit of x)
# 2. If y >= p: not on curve (invalid field element)
# 3. Compute u = y² - 1 (mod p)
# 4. Compute v = d·y² + 1 (mod p)
# 5. Compute x² = u · v⁻¹ (mod p), where v⁻¹ = v^(p-2) (Fermat)
# 6. Euler's criterion: if x²^((p-1)/2) ≡ 1 (mod p), then x exists → ON curve
#    If ≡ p-1, no x exists → OFF curve. If x² = 0, x = 0 → ON curve.
```

**Validated against known values:**
- Known Ed25519 pubkey (RFC 8032 test 1): correctly detected as ON curve
- System program (32 zero bytes): correctly detected as ON curve (y=0 is a valid point)
- ~50% of random SHA-256 outputs are on curve (matches expectation for quadratic residues mod p)

### Module

```elixir
defmodule Signet.Solana.PDA do
  @doc """
  Find a program-derived address from seeds and a program ID.

  Returns {address, bump_seed} where bump_seed is the value (255..0)
  that produces an off-curve address.
  """
  @spec find_program_address([binary()], <<_::256>>) :: {<<_::256>>, non_neg_integer()}
  def find_program_address(seeds, program_id)

  @doc """
  Create a program address from seeds (including bump) and program ID.

  Returns {:ok, address} if off-curve, {:error, :on_curve} if on curve.
  This is the single-attempt version (caller provides the bump seed).
  """
  @spec create_program_address([binary()], <<_::256>>) :: {:ok, <<_::256>>} | {:error, :on_curve}
  def create_program_address(seeds, program_id)
end
```

---

## Layer 2: Associated Token Accounts (ATAs)

### What

An ATA is the **canonical** token account address for a given (wallet, mint) pair. It's a PDA derived with specific seeds:

```
seeds = [wallet_pubkey, token_program_id, mint_pubkey]
program = ATA_PROGRAM_ID
```

When someone says "send me USDC", they mean "send to my ATA for the USDC mint". ATAs remove the need to manually create and track token accounts.

### Known Program IDs

```elixir
@token_program       Signet.Base58.decode!("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
@token_2022_program  Signet.Base58.decode!("TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb")
@ata_program         Signet.Base58.decode!("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
@system_program      <<0::256>>
```

### Module

```elixir
defmodule Signet.Solana.ATA do
  @doc """
  Derive the associated token account address for a wallet + mint.

  Returns {ata_address, bump_seed}. This is a pure computation (no RPC call).

  The token_program defaults to the standard SPL Token Program.
  Pass `:token_program` option for Token-2022 mints.
  """
  @spec find_address(<<_::256>>, <<_::256>>, keyword()) :: {<<_::256>>, non_neg_integer()}
  def find_address(wallet, mint, opts \\ [])

  @doc """
  Build an instruction to create an ATA. Fails if it already exists.
  """
  @spec create(<<_::256>>, <<_::256>>, <<_::256>>, keyword()) :: Instruction.t()
  def create(payer, wallet, mint, opts \\ [])

  @doc """
  Build an instruction to create an ATA, succeeding even if it already exists.
  This is the preferred variant for most use cases.
  """
  @spec create_idempotent(<<_::256>>, <<_::256>>, <<_::256>>, keyword()) :: Instruction.t()
  def create_idempotent(payer, wallet, mint, opts \\ [])
end
```

### ATA Create Instruction

The ATA program's instructions:
- Index 0: Create (fails if exists)
- Index 1: Create Idempotent (no-op if exists)

Accounts for both:
```
0: payer          (writable, signer) - pays for account creation
1: ata            (writable)         - the ATA to create
2: wallet         ()                 - the wallet that will own the ATA
3: mint           ()                 - the token mint
4: system_program ()                 - for account creation
5: token_program  ()                 - SPL Token or Token-2022
```

Data: just the instruction index byte (`<<0>>` or `<<1>>`).

---

## Layer 3: Token Program Instructions

### Module

```elixir
defmodule Signet.Solana.TokenProgram do
  @moduledoc """
  Instruction builders for the SPL Token Program.

  Works with both Token and Token-2022 via the `:token_program` option.
  """

  @doc "Transfer tokens between accounts (authority must sign)."
  @spec transfer(<<_::256>>, <<_::256>>, <<_::256>>, non_neg_integer(), keyword()) :: Instruction.t()
  def transfer(source, destination, authority, amount, opts \\ [])
  # Data: <<3, amount::little-u64>>

  @doc """
  Transfer tokens with decimal check (preferred over transfer/5).
  Requires passing the mint - prevents wrong-decimal mistakes.
  """
  @spec transfer_checked(<<_::256>>, <<_::256>>, <<_::256>>, <<_::256>>, non_neg_integer(), non_neg_integer(), keyword()) :: Instruction.t()
  def transfer_checked(source, mint, destination, authority, amount, decimals, opts \\ [])
  # Data: <<12, amount::little-u64, decimals::u8>>

  @doc "Approve a delegate to transfer up to `amount` tokens."
  @spec approve(<<_::256>>, <<_::256>>, <<_::256>>, non_neg_integer(), keyword()) :: Instruction.t()
  def approve(source, delegate, authority, amount, opts \\ [])
  # Data: <<4, amount::little-u64>>

  @doc "Close a token account, transferring remaining SOL rent to destination."
  @spec close_account(<<_::256>>, <<_::256>>, <<_::256>>, keyword()) :: Instruction.t()
  def close_account(account, destination, authority, opts \\ [])
  # Data: <<9>>

  @doc "Sync the native SOL balance of a wrapped SOL token account."
  @spec sync_native(<<_::256>>, keyword()) :: Instruction.t()
  def sync_native(account, opts \\ [])
  # Data: <<17>>
end
```

### Instruction Encoding

SPL Token uses a **1-byte** instruction index (unlike System Program's 4-byte u32):

| Index | Instruction | Data Layout |
|-------|-------------|-------------|
| 3 | Transfer | `<<3, amount::little-u64>>` |
| 4 | Approve | `<<4, amount::little-u64>>` |
| 7 | MintTo | `<<7, amount::little-u64>>` |
| 9 | CloseAccount | `<<9>>` |
| 12 | TransferChecked | `<<12, amount::little-u64, decimals::u8>>` |
| 17 | SyncNative | `<<17>>` |

---

## Layer 4: `Signet.Solana.Token` (High-Level RPC + Utilities)

This is the "batteries included" module that combines PDA derivation, RPC calls, and instruction building into convenient functions. Analogous to `Signet.Erc20` on the Ethereum side.

### How Token Balance Queries Work

**Get balance for a specific token**: Two approaches:
1. Derive the ATA address, then call `getTokenAccountBalance(ata_address)` - simple but only covers the canonical ATA
2. Call `getTokenAccountsByOwner(wallet, {mint: mint_pubkey})` with `jsonParsed` encoding - returns ALL token accounts for that mint, including non-ATA accounts

Approach 2 is more complete. The RPC node handles figuring out which token program the mint belongs to, so the caller doesn't need to know.

**Get all token balances**: Call `getTokenAccountsByOwner(wallet, {programId: TOKEN_PROGRAM_ID})` with `jsonParsed` encoding. This returns every token account the wallet owns under that program. Repeat for Token-2022 to get full coverage. The `jsonParsed` encoding gives us structured data (mint, balance, decimals) without needing to deserialize the account data ourselves.

### New RPC Method Needed

Add to `Signet.Solana.RPC`:

```elixir
@doc """
Get all token accounts owned by a wallet.

Filter by `:mint` (specific token) or `:program_id` (all tokens under a program).
"""
@spec get_token_accounts_by_owner(<<_::256>>, keyword(), keyword()) ::
        {:ok, [%{pubkey: binary(), account: map()}]} | {:error, term()}
def get_token_accounts_by_owner(owner, filter, opts \\ [])
# filter: [mint: <<_::256>>] or [program_id: <<_::256>>]
```

### Module

```elixir
defmodule Signet.Solana.Token do
  @moduledoc """
  High-level token operations: balance queries, transfers, ATA management.
  Combines RPC calls with PDA derivation and instruction building.
  """

  @doc """
  Get the balance of a specific token for a wallet.

  Finds all token accounts for the (wallet, mint) pair and sums the balance.
  Most wallets have exactly one (the ATA), but this handles edge cases.

  Returns the total amount as a raw integer (not adjusted for decimals)
  along with the decimals and mint info.
  """
  @spec get_balance(<<_::256>>, <<_::256>>, keyword()) ::
          {:ok, %{amount: non_neg_integer(), decimals: non_neg_integer(), mint: String.t()}}
          | {:error, term()}
  def get_balance(wallet, mint, opts \\ [])

  @doc """
  Get all token balances for a wallet.

  Queries both Token Program and Token-2022 by default.
  Returns a list of balances with mint addresses.

  Options:
  - `:include_token_2022` - also query Token-2022 (default: true)
  """
  @spec get_all_balances(<<_::256>>, keyword()) ::
          {:ok, [%{mint: String.t(), amount: non_neg_integer(), decimals: non_neg_integer(), token_account: String.t()}]}
          | {:error, term()}
  def get_all_balances(wallet, opts \\ [])

  @doc """
  Build a token transfer transaction.

  Handles ATA derivation for source and destination, creates destination
  ATA if needed (via create_idempotent), and builds the transfer instruction.

  Returns a list of instructions (may include ATA creation + transfer).
  """
  @spec transfer_instructions(<<_::256>>, <<_::256>>, <<_::256>>, non_neg_integer(), non_neg_integer(), keyword()) ::
          [Instruction.t()]
  def transfer_instructions(from_wallet, to_wallet, mint, amount, decimals, opts \\ [])
end
```

### `get_balance/3` Implementation Sketch

```elixir
def get_balance(wallet, mint, opts) do
  with {:ok, accounts} <- RPC.get_token_accounts_by_owner(wallet, [mint: mint], opts ++ [encoding: :json_parsed]) do
    case accounts do
      [] ->
        {:ok, %{amount: 0, decimals: 0, mint: Signet.Base58.encode(mint)}}
      accounts ->
        # Sum balances across all accounts for this mint (usually just one ATA)
        {total, decimals} = Enum.reduce(accounts, {0, 0}, fn acct, {sum, _dec} ->
          info = acct.account.data["parsed"]["info"]
          amount = String.to_integer(info["tokenAmount"]["amount"])
          decimals = info["tokenAmount"]["decimals"]
          {sum + amount, decimals}
        end)

        {:ok, %{amount: total, decimals: decimals, mint: Signet.Base58.encode(mint)}}
    end
  end
end
```

### `get_all_balances/2` Implementation Sketch

```elixir
def get_all_balances(wallet, opts) do
  include_2022 = Keyword.get(opts, :include_token_2022, true)

  with {:ok, token_accounts} <- RPC.get_token_accounts_by_owner(wallet, [program_id: @token_program], opts ++ [encoding: :json_parsed]) do
    balances = parse_token_accounts(token_accounts)

    if include_2022 do
      case RPC.get_token_accounts_by_owner(wallet, [program_id: @token_2022_program], opts ++ [encoding: :json_parsed]) do
        {:ok, token_2022_accounts} ->
          {:ok, balances ++ parse_token_accounts(token_2022_accounts)}
        {:error, _} ->
          # Token-2022 query failing shouldn't break the whole call
          {:ok, balances}
      end
    else
      {:ok, balances}
    end
  end
end
```

### `transfer_instructions/6` Implementation Sketch

```elixir
def transfer_instructions(from_wallet, to_wallet, mint, amount, decimals, opts) do
  {from_ata, _} = Signet.Solana.ATA.find_address(from_wallet, mint, opts)
  {to_ata, _} = Signet.Solana.ATA.find_address(to_wallet, mint, opts)

  # Create destination ATA if needed (idempotent - no-op if exists)
  create_ix = Signet.Solana.ATA.create_idempotent(from_wallet, to_wallet, mint, opts)

  # Transfer
  transfer_ix = Signet.Solana.TokenProgram.transfer_checked(
    from_ata, mint, to_ata, from_wallet, amount, decimals, opts
  )

  [create_ix, transfer_ix]
end
```

---

## Also in this Phase: `Signet.Solana.Programs` Constants

We keep defining program IDs in scattered places. Central module for well-known addresses:

```elixir
defmodule Signet.Solana.Programs do
  use Signet.Base58

  def system_program,          do: <<0::256>>
  def token_program,           do: ~B58[TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA]
  def token_2022_program,      do: ~B58[TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb]
  def ata_program,             do: ~B58[ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL]
  def compute_budget_program,  do: ~B58[ComputeBudget111111111111111111111111111111]
  def wrapped_sol_mint,        do: ~B58[So11111111111111111111111111111111111111112]
end
```

`SystemProgram.program_id/0` can delegate to this.

---

## Implementation Order

1. **`Signet.Solana.Programs`** - Central program ID constants (uses `~B58` sigil)

2. **`Signet.Solana.PDA`** - `find_program_address/2`, `create_program_address/2`
   - "On curve" check via Ed25519 point decompression (validated, uses `:crypto.mod_pow/3`)
   - Pure computation, no RPC

3. **`Signet.Solana.ATA`** - `find_address/3`, `create/4`, `create_idempotent/4`
   - Depends on PDA + Programs
   - Pure computation for find, instruction building for create

4. **`Signet.Solana.TokenProgram`** - instruction builders
   - `transfer/5`, `transfer_checked/7`, `approve/5`, `close_account/4`, `sync_native/2`
   - Pure instruction building, no RPC

5. **`Signet.Solana.RPC.get_token_accounts_by_owner/3`** - new RPC method

6. **`Signet.Solana.Token`** - high-level RPC + utilities
   - `get_balance/3`, `get_all_balances/2`, `transfer_instructions/6`
   - Depends on everything above

---

## Test Plan

### PDA
- **"On curve" check**:
  - Known Ed25519 public keys (RFC 8032 vectors) must be detected as ON curve
  - System program address (32 zero bytes) must be detected as ON curve
  - PDA outputs from `find_program_address` must be detected as OFF curve
  - Statistical: ~50% of random SHA-256 outputs should be on curve
- **Known PDA derivations**: Cross-validate against Solana CLI (`solana-keygen find-program-derived-address`) or web3.js for known (seeds, program_id) → (address, bump) tuples
- **Bump seed**: Verify the returned bump matches expected values
- **Edge cases**: Empty seeds list, max-length seeds, seed that requires bump < 255

### ATA
- Derive known ATA addresses for well-known (wallet, mint) pairs, cross-validate with web3.js or on-chain data
- `create` instruction: correct 6 accounts in correct order, data = `<<0>>`
- `create_idempotent` instruction: same accounts, data = `<<1>>`
- Token-2022 option changes the token_program account in the instruction

### TokenProgram
- Transfer: data = `<<3, amount::little-u64>>`, accounts = [source, destination, authority]
- TransferChecked: data = `<<12, amount::little-u64, decimals::u8>>`, accounts = [source, mint, destination, authority]
- Approve: data = `<<4, amount::little-u64>>`, accounts = [source, delegate, authority]
- CloseAccount: data = `<<9>>`, accounts = [account, destination, authority]
- SyncNative: data = `<<17>>`, accounts = [account]
- All with correct signer/writable permission flags
- Token-2022 option changes program_id

### Token (RPC layer)
- `get_balance` with mock `getTokenAccountsByOwner` jsonParsed response → correct deserialization
- `get_balance` for wallet with no token accounts → `%{amount: 0, ...}`
- `get_balance` for wallet with multiple accounts for same mint → sums correctly
- `get_all_balances` combines Token + Token-2022 results
- `get_all_balances` with `include_token_2022: false` → only queries Token Program
- `transfer_instructions` returns `[create_idempotent_ix, transfer_checked_ix]`
- All with full assertions on complete response structures

---

## Decisions

- **`Signet.Solana.Programs` for centralized constants**: Avoids scattered Base58 decoding and keeps program IDs in one place. Uses `~B58` sigil for compile-time decoding.
- **`Signet.Solana.Token` as the high-level module**: Combines RPC + computation, analogous to `Signet.Erc20`.
- **Token-2022 included by default**: `get_all_balances` queries both programs. Most users won't think about this distinction.
- **`transfer_instructions` always includes create_idempotent**: Safer default. The create is a no-op if the ATA exists, and costs nothing extra in that case.
- **`jsonParsed` encoding for balance queries**: The RPC node parses the token account data for us, so we don't need to implement SPL Token account deserialization initially.
- **Token program as option, not separate modules**: `TokenProgram.transfer(..., token_program: @token_2022)` rather than separate `Token2022Program` module. The instructions are identical.
- **"On curve" via pure math**: OTP's `:crypto.verify/5` can't distinguish invalid keys from bad signatures. We implement the Ed25519 quadratic residue check using `:crypto.mod_pow/3` (C-implemented, fast). ~20 lines of modular arithmetic, validated against known values.
- **Return instructions, not transactions**: `transfer_instructions/6` returns a list of instructions. The caller composes them into a transaction with their own fee payer, blockhash, and additional instructions. This is more flexible (e.g., for sponsored transactions where the fee payer differs from the token authority).

## Open Questions

- **PDA test vectors**: We need known (seeds, program_id) → (address, bump) pairs. Best source: generate them with `solana-keygen` or web3.js `PublicKey.findProgramAddressSync()` and hardcode as test fixtures.
- **Account data deserialization**: For `jsonParsed` responses we rely on the RPC node. Should we also support deserializing raw token account data (165 bytes) ourselves? Useful for offline/cached data, but not needed initially.
- **Wrapped SOL**: Should `transfer_instructions` detect the native SOL mint and handle wrapping/unwrapping? This is a common footgun but adds complexity. Probably a separate helper.

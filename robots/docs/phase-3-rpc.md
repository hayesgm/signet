# Phase 3: Solana RPC Client

**Module:** `Signet.Solana.RPC`
**Dependencies:** `Signet.Base58` (Phase 0), `Signet.Solana.Transaction` (Phase 2), Finch (existing)
**Also:** Extract shared JSON-RPC transport from existing `Signet.RPC`

---

## Overview

Solana uses JSON-RPC 2.0, the same transport as Ethereum. We can reuse the Finch HTTP client and JSON-RPC framing from the existing `Signet.RPC`, but all methods, parameters, and response types are Solana-specific.

### Key Differences from Ethereum RPC

| Aspect | Ethereum (`Signet.RPC`) | Solana (`Signet.Solana.RPC`) |
|---|---|---|
| Data encoding | Hex (`0x`-prefix) | Base58, Base64 |
| Block concept | Block numbers | Slots |
| Transaction ID | Keccak hash | First Ed25519 signature (Base58) |
| Nonce | Sequential counter | Recent blockhash (expires ~60-90s) |
| Commitment | `latest`, `safe`, `finalized` | `processed`, `confirmed`, `finalized` |
| Response wrapper | Bare result | Often `{context: {slot}, value: ...}` |
| Error decoding | Solidity ABI errors | Program log messages |

## Pre-requisite: Extract Shared JSON-RPC Transport

Before building `Signet.Solana.RPC`, extract the reusable parts from `Signet.RPC` into a shared module.

### `Signet.RPC.Transport` (or similar)

The following from `Signet.RPC` is generic and reusable:
- `get_body/3` - Build JSON-RPC request body (`{jsonrpc, method, params, id}`)
- HTTP POST via Finch with headers and timeout
- JSON response parsing and `id` matching
- Error extraction from JSON-RPC error responses

What is NOT reusable (stays in `Signet.RPC`):
- Ethereum-specific error decoding (Solidity ABI)
- Transaction building/signing logic
- Gas estimation
- Hex encoding/decoding of params and results

```elixir
defmodule Signet.RPC.Transport do
  @moduledoc """
  Shared JSON-RPC 2.0 transport over HTTP (Finch).
  Used by both Ethereum and Solana RPC clients.
  """

  @doc "Send a JSON-RPC request and return the raw result."
  @spec send_rpc(
    node_url :: String.t(),
    method :: String.t(),
    params :: list(),
    opts :: keyword()
  ) :: {:ok, term()} | {:error, term()}
  def send_rpc(node_url, method, params, opts \\ [])
end
```

**Decision**: This extraction should be a refactor of `Signet.RPC` that preserves its public API. The existing `Signet.RPC.send_rpc/3` can delegate to `Signet.RPC.Transport.send_rpc/4` with the Ethereum node URL.

## Configuration

```elixir
# config.exs or runtime.exs
config :signet,
  solana_node: "https://api.mainnet-beta.solana.com"
  # or devnet: "https://api.devnet.solana.com"
  # or testnet: "https://api.testnet.solana.com"
```

Accessed via:
```elixir
defp solana_node(), do: Application.get_env(:signet, :solana_node)
```

## Type Definitions

### Common Types

```elixir
@type commitment :: :processed | :confirmed | :finalized
@type encoding :: :base58 | :base64 | :"base64+zstd" | :json_parsed
@type pubkey :: binary()  # 32 bytes
@type signature :: String.t()  # Base58-encoded signature
@type lamports :: non_neg_integer()
@type slot :: non_neg_integer()
```

### Response Structs

```elixir
defmodule Signet.Solana.AccountInfo do
  @type t :: %__MODULE__{
    data: binary() | {binary(), String.t()} | map(),
    executable: boolean(),
    lamports: non_neg_integer(),
    owner: binary(),          # 32-byte pubkey
    rent_epoch: non_neg_integer(),
    space: non_neg_integer()
  }
  defstruct [:data, :executable, :lamports, :owner, :rent_epoch, :space]
end

defmodule Signet.Solana.SignatureStatus do
  @type t :: %__MODULE__{
    slot: non_neg_integer(),
    confirmations: non_neg_integer() | nil,
    err: term(),
    confirmation_status: :processed | :confirmed | :finalized | nil
  }
  defstruct [:slot, :confirmations, :err, :confirmation_status]
end

defmodule Signet.Solana.TokenAmount do
  @type t :: %__MODULE__{
    amount: non_neg_integer(),   # parsed from string
    decimals: non_neg_integer(),
    ui_amount_string: String.t()
  }
  defstruct [:amount, :decimals, :ui_amount_string]
end

defmodule Signet.Solana.PrioritizationFee do
  @type t :: %__MODULE__{
    slot: non_neg_integer(),
    prioritization_fee: non_neg_integer()  # micro-lamports per CU
  }
  defstruct [:slot, :prioritization_fee]
end
```

## RPC Methods

### Read Operations

#### `get_balance/2`
```elixir
@spec get_balance(pubkey :: binary(), opts :: keyword()) ::
  {:ok, non_neg_integer()} | {:error, term()}
def get_balance(pubkey, opts \\ [])
# opts: [commitment: :finalized]
# RPC: "getBalance", [Base58.encode(pubkey), %{commitment: ...}]
# Returns: lamports (integer)
```

#### `get_account_info/2`
```elixir
@spec get_account_info(pubkey :: binary(), opts :: keyword()) ::
  {:ok, Signet.Solana.AccountInfo.t() | nil} | {:error, term()}
def get_account_info(pubkey, opts \\ [])
# opts: [commitment: :finalized, encoding: :base64]
# Returns: nil if account doesn't exist
```

#### `get_multiple_accounts/2`
```elixir
@spec get_multiple_accounts(pubkeys :: [binary()], opts :: keyword()) ::
  {:ok, [Signet.Solana.AccountInfo.t() | nil]} | {:error, term()}
def get_multiple_accounts(pubkeys, opts \\ [])
# Max 100 pubkeys
```

#### `get_latest_blockhash/1`
```elixir
@spec get_latest_blockhash(opts :: keyword()) ::
  {:ok, %{blockhash: binary(), last_valid_block_height: non_neg_integer()}} | {:error, term()}
def get_latest_blockhash(opts \\ [])
# The blockhash is returned as raw 32 bytes (decoded from Base58)
```

#### `get_slot/1`
```elixir
@spec get_slot(opts :: keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
def get_slot(opts \\ [])
```

#### `get_block_height/1`
```elixir
@spec get_block_height(opts :: keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
def get_block_height(opts \\ [])
```

#### `get_transaction/2`
```elixir
@spec get_transaction(signature :: String.t(), opts :: keyword()) ::
  {:ok, map() | nil} | {:error, term()}
def get_transaction(signature, opts \\ [])
# opts: [commitment: :finalized, encoding: :json]
# Returns nil if not found
# Full transaction response struct (complex, see below)
```

Note: `getTransaction` has a complex response. We'll start with returning the raw decoded map and add a typed struct later as we understand all the fields.

#### `get_signature_statuses/2`
```elixir
@spec get_signature_statuses(signatures :: [String.t()], opts :: keyword()) ::
  {:ok, [Signet.Solana.SignatureStatus.t() | nil]} | {:error, term()}
def get_signature_statuses(signatures, opts \\ [])
# opts: [search_transaction_history: false]
# Max 256 signatures
```

#### `get_minimum_balance_for_rent_exemption/2`
```elixir
@spec get_minimum_balance_for_rent_exemption(data_length :: non_neg_integer(), opts :: keyword()) ::
  {:ok, non_neg_integer()} | {:error, term()}
def get_minimum_balance_for_rent_exemption(data_length, opts \\ [])
```

#### `get_token_account_balance/2`
```elixir
@spec get_token_account_balance(pubkey :: binary(), opts :: keyword()) ::
  {:ok, Signet.Solana.TokenAmount.t()} | {:error, term()}
def get_token_account_balance(pubkey, opts \\ [])
```

#### `get_token_accounts_by_owner/3`
```elixir
@spec get_token_accounts_by_owner(owner :: binary(), filter :: keyword(), opts :: keyword()) ::
  {:ok, [%{pubkey: binary(), account: Signet.Solana.AccountInfo.t()}]} | {:error, term()}
def get_token_accounts_by_owner(owner, filter, opts \\ [])
# filter: [mint: pubkey] or [program_id: pubkey]
```

### Write Operations

#### `send_transaction/2`
```elixir
@spec send_transaction(transaction :: binary() | Signet.Solana.Transaction.t(), opts :: keyword()) ::
  {:ok, String.t()} | {:error, term()}
def send_transaction(transaction, opts \\ [])
# opts: [encoding: :base64, skip_preflight: false, preflight_commitment: :finalized]
# Accepts raw serialized bytes or a Transaction struct (will serialize)
# Returns: transaction signature (Base58 string)
```

#### `simulate_transaction/2`
```elixir
@spec simulate_transaction(transaction :: binary() | Signet.Solana.Transaction.t(), opts :: keyword()) ::
  {:ok, map()} | {:error, term()}
def simulate_transaction(transaction, opts \\ [])
# Returns simulation result with logs, compute units, etc.
```

### Utility Operations

#### `request_airdrop/3`
```elixir
@spec request_airdrop(pubkey :: binary(), lamports :: non_neg_integer(), opts :: keyword()) ::
  {:ok, String.t()} | {:error, term()}
def request_airdrop(pubkey, lamports, opts \\ [])
# Devnet/testnet only. Returns airdrop tx signature.
```

#### `get_recent_prioritization_fees/1`
```elixir
@spec get_recent_prioritization_fees(addresses :: [binary()]) ::
  {:ok, [Signet.Solana.PrioritizationFee.t()]} | {:error, term()}
def get_recent_prioritization_fees(addresses \\ [])
# Max 128 addresses
```

#### `get_health/1`
```elixir
@spec get_health(opts :: keyword()) :: :ok | {:error, term()}
def get_health(opts \\ [])
# Special: unhealthy returns a JSON-RPC error, not a result
```

#### `get_version/1`
```elixir
@spec get_version(opts :: keyword()) ::
  {:ok, %{solana_core: String.t(), feature_set: non_neg_integer()}} | {:error, term()}
def get_version(opts \\ [])
```

### High-Level Helpers

#### `send_and_confirm/2`
```elixir
@spec send_and_confirm(transaction :: Signet.Solana.Transaction.t(), opts :: keyword()) ::
  {:ok, String.t()} | {:error, term()}
def send_and_confirm(transaction, opts \\ [])
# opts: [commitment: :confirmed, timeout: 30_000, poll_interval: 500]
# Sends transaction, then polls getSignatureStatuses until confirmed/finalized or timeout
```

## Response Deserialization Pattern

Following existing Signet patterns (e.g., `Signet.Block.deserialize/1`, `Signet.Receipt.deserialize/1`), each response struct has a `deserialize/1` function that takes the raw JSON-decoded map.

```elixir
defmodule Signet.Solana.AccountInfo do
  def deserialize(nil), do: nil

  def deserialize(%{
    "data" => data,
    "executable" => executable,
    "lamports" => lamports,
    "owner" => owner_base58,
    "rentEpoch" => rent_epoch,
    "space" => space
  }) do
    %__MODULE__{
      data: deserialize_data(data),
      executable: executable,
      lamports: lamports,
      owner: Base58.decode!(owner_base58),
      rent_epoch: rent_epoch,
      space: space
    }
  end
end
```

### Handling the RpcResponse Wrapper

Many Solana methods return `{context: {slot}, value: ...}`. We need a helper:

```elixir
defp unwrap_rpc_response(%{"context" => %{"slot" => _slot}, "value" => value}) do
  value
end
```

For now, we discard the context slot. If needed later, we can return it as metadata.

## Response Shape Categories

| Pattern | Methods | Approach |
|---------|---------|----------|
| `{context, value}` wrapper | getBalance, getAccountInfo, getMultipleAccounts, getLatestBlockhash, getSignatureStatuses, simulateTransaction, getTokenAccountBalance, getTokenAccountsByOwner | Unwrap, deserialize value |
| Bare scalar | getSlot, getBlockHeight, getMinimumBalanceForRentExemption, sendTransaction, requestAirdrop | Return directly |
| Bare object | getVersion, getTransaction | Deserialize directly |
| Bare array | getRecentPrioritizationFees | Deserialize each element |
| String / Error | getHealth | Special handling |

## Test Plan

### Transport Tests

- `send_rpc/4` correctly builds JSON-RPC body
- Correct Finch HTTP call with headers and timeout
- JSON response parsing and id matching
- Error response handling

### Mock-Based Unit Tests

For each RPC method, test with canned JSON responses:
- Successful responses deserialize to correct structs
- Null values handled (e.g., account not found)
- Error responses returned as `{:error, ...}`

### Integration Tests (against devnet, tagged `:integration`)

```elixir
@tag :integration
test "get_balance returns lamports" do
  # Use a known devnet address
  {:ok, balance} = Signet.Solana.RPC.get_balance(some_pubkey)
  assert is_integer(balance) and balance >= 0
end
```

Integration tests should:
- Connect to Solana devnet
- Use `request_airdrop` for test setup
- Test full roundtrip: airdrop → check balance → build transfer → send → confirm

### Full Transaction Roundtrip Test (Integration)

1. Generate two keypairs
2. Airdrop SOL to keypair A
3. Build a transfer instruction (A → B)
4. Fetch latest blockhash
5. Build and sign transaction
6. Send transaction
7. Poll for confirmation
8. Verify B's balance increased

## File Layout

```
lib/signet/rpc/transport.ex              # Shared JSON-RPC transport
lib/signet/solana/rpc.ex                 # Signet.Solana.RPC
lib/signet/solana/account_info.ex        # AccountInfo struct
lib/signet/solana/signature_status.ex    # SignatureStatus struct
lib/signet/solana/token_amount.ex        # TokenAmount struct
lib/signet/solana/prioritization_fee.ex  # PrioritizationFee struct
test/solana/rpc_test.exs                 # unit tests with mocks
test/solana/rpc_integration_test.exs     # integration tests (tagged)
```

## Decisions

- **Extract shared transport**: `Signet.RPC.Transport` handles JSON-RPC framing. Both `Signet.RPC` and `Signet.Solana.RPC` use it.
- **Accept binary pubkeys, encode to Base58 internally**: The public API takes 32-byte binary pubkeys (consistent with how keys are stored). The RPC module encodes to Base58 strings for JSON-RPC params.
- **Default encoding: base64**: For `sendTransaction` and account data queries, base64 is recommended over base58 (faster, no size limit).
- **Default commitment: :finalized**: Safest default. Users can override per-call.
- **Discard context slot initially**: The `{context: {slot}, value}` wrapper's slot is useful for consistency checks but not critical. We can add it later.
- **`get_transaction` returns raw map initially**: The response is very complex with many nested types. Start with raw map, add typed struct iteratively.

## Open Questions

- **Should `send_transaction` accept a `Transaction` struct or raw bytes?** Both. If given a struct, serialize it. If given bytes, pass through.
- **WebSocket subscriptions?** Solana supports `accountSubscribe`, `signatureSubscribe`, etc. These would be a separate module (`Signet.Solana.WS`). Out of scope for phase 3.
- **Batch requests?** JSON-RPC supports batch requests (send array of requests, get array of responses). Could be useful for `get_multiple_accounts` alternatives. Consider for later.
- **Rate limiting / retry?** Solana public RPC endpoints are rate-limited. Should the client handle retries? Probably not in the library itself - let the caller handle it.

# Phase 2: Solana Transaction Building and Serialization

**Modules:** `Signet.Solana.Transaction`, `Signet.Solana.SystemProgram`
**Dependencies:** `Signet.Base58` (Phase 0), `Signet.Solana.Keys` / `Signet.Solana.Signer` (Phase 1)
**Prerequisite for:** RPC write operations (Phase 3)

---

## Overview

Solana transactions use a custom binary serialization format (not RLP, not protobuf, not borsh). The format is compact and uses variable-length integers ("compact-u16") for array lengths.

A transaction consists of:
1. **Signatures** - Array of 64-byte Ed25519 signatures
2. **Message** - The payload that was signed

The serialized message bytes are what each signer signs directly (Ed25519 handles hashing internally). The first signature also serves as the **transaction ID**.

## Transaction Wire Format

```
Transaction:
  compact_u16(num_signatures)
  [signature; 64 bytes] × num_signatures
  Message (see below)

Message (legacy):
  Header:
    u8  num_required_signatures
    u8  num_readonly_signed_accounts
    u8  num_readonly_unsigned_accounts
  compact_u16(num_account_keys)
  [pubkey; 32 bytes] × num_account_keys
  recent_blockhash: 32 bytes
  compact_u16(num_instructions)
  CompiledInstruction × num_instructions

CompiledInstruction:
  u8  program_id_index          (index into account_keys)
  compact_u16(num_accounts)
  [u8 account_index] × num_accounts
  compact_u16(data_length)
  [u8] × data_length
```

### Account Key Ordering

The account keys array is strictly ordered by permission level:
1. **Writable signers** (fee payer is always first)
2. **Read-only signers**
3. **Writable non-signers**
4. **Read-only non-signers**

The header counts tell you where each group ends:
- Indices `[0, num_required_signatures)` are signers
- Of those, `[num_required_signatures - num_readonly_signed, num_required_signatures)` are read-only
- Indices `[num_required_signatures, total - num_readonly_unsigned)` are writable non-signers
- Indices `[total - num_readonly_unsigned, total)` are read-only non-signers

### Compact-u16 Encoding

Variable-length unsigned integer encoding (like Bitcoin's CompactSize but for u16 range):

| Value Range | Bytes | Encoding |
|-------------|-------|----------|
| 0 - 127 | 1 | `[value]` |
| 128 - 16383 | 2 | `[value & 0x7F \| 0x80, value >> 7]` |
| 16384 - 65535 | 3 | `[value & 0x7F \| 0x80, (value >> 7) & 0x7F \| 0x80, value >> 14]` |

Each byte uses 7 data bits with the high bit as a continuation flag (1 = more bytes follow).

## Implementation Plan

### `Signet.Solana.Transaction`

```elixir
defmodule Signet.Solana.Transaction do
  @moduledoc """
  Build, serialize, and sign Solana transactions.
  """

  defmodule Instruction do
    @moduledoc "A high-level instruction before compilation."
    @type t :: %__MODULE__{
      program_id: binary(),           # 32-byte pubkey
      accounts: [AccountMeta.t()],
      data: binary()
    }
    defstruct [:program_id, :accounts, :data]
  end

  defmodule AccountMeta do
    @moduledoc "Account reference with permission flags."
    @type t :: %__MODULE__{
      pubkey: binary(),     # 32-byte pubkey
      is_signer: boolean(),
      is_writable: boolean()
    }
    defstruct [:pubkey, :is_signer, :is_writable]
  end

  defmodule Header do
    @type t :: %__MODULE__{
      num_required_signatures: non_neg_integer(),
      num_readonly_signed_accounts: non_neg_integer(),
      num_readonly_unsigned_accounts: non_neg_integer()
    }
    defstruct [:num_required_signatures, :num_readonly_signed_accounts,
               :num_readonly_unsigned_accounts]
  end

  defmodule CompiledInstruction do
    @type t :: %__MODULE__{
      program_id_index: non_neg_integer(),
      accounts: [non_neg_integer()],
      data: binary()
    }
    defstruct [:program_id_index, :accounts, :data]
  end

  defmodule Message do
    @type t :: %__MODULE__{
      header: Header.t(),
      account_keys: [binary()],         # list of 32-byte pubkeys
      recent_blockhash: binary(),        # 32 bytes
      instructions: [CompiledInstruction.t()]
    }
    defstruct [:header, :account_keys, :recent_blockhash, :instructions]
  end

  @type t :: %__MODULE__{
    signatures: [binary()],     # list of 64-byte signatures
    message: Message.t()
  }
  defstruct [:signatures, :message]

  # --- Building ---

  @doc """
  Build a transaction message from high-level instructions.
  Handles account deduplication, ordering, and index compilation.
  """
  @spec build_message(
    fee_payer :: binary(),
    instructions :: [Instruction.t()],
    recent_blockhash :: binary()
  ) :: Message.t()
  def build_message(fee_payer, instructions, recent_blockhash)

  # --- Serialization ---

  @doc "Serialize a Message to the bytes that get signed."
  @spec serialize_message(Message.t()) :: binary()
  def serialize_message(message)

  @doc "Serialize a full transaction (signatures + message) for RPC submission."
  @spec serialize(t()) :: binary()
  def serialize(transaction)

  @doc "Deserialize a transaction from binary."
  @spec deserialize(binary()) :: {:ok, t()} | {:error, term()}
  def deserialize(binary)

  # --- Signing ---

  @doc "Sign a message and produce a full transaction."
  @spec sign(Message.t(), [binary()]) :: t()
  def sign(message, seeds)
  # seeds is a list of 32-byte seeds, ordered to match signer positions

  # --- Compact-u16 helpers ---

  @doc "Encode a non-negative integer as a compact-u16."
  @spec encode_compact_u16(non_neg_integer()) :: binary()
  def encode_compact_u16(value)

  @doc "Decode a compact-u16 from binary, returning {value, rest}."
  @spec decode_compact_u16(binary()) :: {non_neg_integer(), binary()}
  def decode_compact_u16(binary)
end
```

### `build_message/3` Logic (the tricky part)

Building a message from high-level instructions requires:

1. **Collect all accounts** from all instructions + fee payer
2. **Deduplicate** by pubkey, merging permissions (if any reference is writable, the account is writable; if any reference is signer, it's a signer)
3. **Sort** into the four groups: writable-signer, readonly-signer, writable-nonsigner, readonly-nonsigner
4. **Ensure fee payer** is first (always writable + signer)
5. **Compile instructions** by replacing pubkeys with indices into the sorted account list
6. **Compute header** counts from the sorted groups

### `Signet.Solana.SystemProgram`

The System Program (address: `11111111111111111111111111111111`, all zero bytes) handles basic operations. Good first test case for the transaction builder.

```elixir
defmodule Signet.Solana.SystemProgram do
  @moduledoc """
  Instructions for the Solana System Program.
  """

  @system_program_id <<0::256>>

  @doc """
  Build a transfer instruction (SOL transfer).

  System Program instruction index 2 (Transfer).
  Data: little-endian u32 instruction index (2) + little-endian u64 lamports
  """
  @spec transfer(
    from :: binary(),
    to :: binary(),
    lamports :: non_neg_integer()
  ) :: Signet.Solana.Transaction.Instruction.t()
  def transfer(from, to, lamports)

  @doc """
  Build a create_account instruction.

  System Program instruction index 0 (CreateAccount).
  Data: u32 index (0) + u64 lamports + u64 space + 32-byte owner pubkey
  """
  @spec create_account(
    from :: binary(),
    new_account :: binary(),
    lamports :: non_neg_integer(),
    space :: non_neg_integer(),
    owner :: binary()
  ) :: Signet.Solana.Transaction.Instruction.t()
  def create_account(from, new_account, lamports, space, owner)
end
```

### System Program Instruction Encoding

The System Program uses a simple encoding: a little-endian u32 instruction index followed by instruction-specific data.

**Transfer (index 2):**
```
<< 2::little-unsigned-32, lamports::little-unsigned-64 >>
```
Accounts: `[from (writable, signer), to (writable)]`

**CreateAccount (index 0):**
```
<< 0::little-unsigned-32, lamports::little-unsigned-64, space::little-unsigned-64, owner::binary-32 >>
```
Accounts: `[from (writable, signer), new_account (writable, signer)]`

## Test Plan

### Compact-u16 Encoding

| Value | Encoded (hex) |
|-------|---------------|
| 0 | `00` |
| 1 | `01` |
| 127 | `7f` |
| 128 | `8001` |
| 255 | `ff01` |
| 256 | `8002` |
| 16383 | `ff7f` |
| 16384 | `808001` |

### Message Serialization

Build a simple SOL transfer message and verify the serialized bytes match known-good output. We can cross-reference with:
- The Solana web3.js library's output for the same transaction
- A real transaction from Solana Explorer (deserialize and re-serialize)

### Account Ordering

Test that `build_message/3` correctly:
- Deduplicates accounts referenced by multiple instructions
- Merges permissions (writable wins over readonly, signer wins over non-signer)
- Places fee payer first
- Orders: writable-signers, readonly-signers, writable-nonsigners, readonly-nonsigners
- Computes correct header counts

### Sign and Serialize Roundtrip

1. Build a transfer message
2. Sign it with a known keypair
3. Serialize the full transaction
4. Deserialize it back
5. Verify all fields match
6. Verify the signature is valid

### System Program Instructions

- Transfer instruction serializes to the correct bytes
- CreateAccount instruction serializes to the correct bytes
- Instructions produce correct AccountMeta entries

### Cross-Validation with Real Transactions

Fetch a known simple SOL transfer from Solana Explorer (devnet), deserialize it, and verify our serializer produces identical bytes. This is the strongest correctness check.

## File Layout

```
lib/signet/solana/transaction.ex      # Transaction, Message, Instruction, etc.
lib/signet/solana/system_program.ex   # SystemProgram
test/solana/transaction_test.exs      # serialization + building tests
test/solana/system_program_test.exs   # instruction encoding tests
```

## Decisions

- **Start with legacy transactions only.** Versioned (v0) transactions with address lookup tables can come later. Legacy covers all basic use cases.
- **High-level Instruction → compiled Message pattern.** Users build `Instruction` structs with pubkeys and data, then `build_message/3` handles all the compilation to indices. This is the same pattern used by Solana's web3.js and Rust SDK.
- **System Program first.** It's the simplest program, and SOL transfers are the most basic operation. Good for validating the transaction builder.
- **Little-endian for instruction data.** Solana programs expect little-endian encoding (it runs on x86). The System Program uses `u32` instruction index + little-endian fields.

## Open Questions

- **Versioned (v0) transactions**: When to add? Probably after basic RPC is working and we hit the account limit on a real use case.
- **Durable nonces**: Solana supports durable nonces (replacing recent blockhash with a nonce account's value) for offline signing. Worth supporting but not in the first pass.
- **Transaction size validation**: Should we validate the 1232-byte limit during serialization? Probably yes, at least as a warning.

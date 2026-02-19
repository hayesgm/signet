# Phase 1: Ed25519 Keys and Signing

**Modules:** `Signet.Solana.Keys`, `Signet.Solana.Signer`, `Signet.Solana.Signer.Ed25519`, `Signet.Solana.Signer.CloudKMS`
**Dependencies:** OTP `:crypto` (built-in, OTP 24+), `Signet.Base58` (Phase 0), `google_api_cloud_kms` (optional, existing dep)
**Prerequisite for:** Transaction building (Phase 2), RPC (Phase 3)

---

## Overview

Solana uses Ed25519 (EdDSA on Curve25519) for all signing. This is fundamentally different from Ethereum's secp256k1 (ECDSA):

| | Ethereum (secp256k1) | Solana (Ed25519) |
|---|---|---|
| Public key | 64 bytes uncompressed → keccak → last 20 bytes = address | 32 bytes = the address itself |
| Private key | 32 bytes | 32-byte seed (stored as 64 bytes: seed + pubkey) |
| Signature | 65 bytes (r, s, v) with recovery bit | 64 bytes (R, S), deterministic, no recovery |
| Digest | Keccak-256 applied externally before signing | SHA-512 applied internally by Ed25519 |
| Recovery | Can recover pubkey from sig + message | Not possible |

**Good news**: OTP natively supports Ed25519 via `:crypto`. No external library needed.

## OTP `:crypto` API

```elixir
# Key generation (random)
{pub, seed} = :crypto.generate_key(:eddsa, :ed25519)
# pub  = <<_::256>>  (32 bytes, the public key / Solana address)
# seed = <<_::256>>  (32 bytes, the seed)

# Key generation (from existing seed)
{pub, ^seed} = :crypto.generate_key(:eddsa, :ed25519, seed)
# Derives public key from 32-byte seed

# Signing
signature = :crypto.sign(:eddsa, :none, message, [seed, :ed25519])
# seed    = 32-byte seed (NOT 64-byte Solana keypair format)
# message = raw bytes (no external hashing needed)
# :none   = no separate digest (Ed25519 uses SHA-512 internally)
# Returns: 64-byte signature

# Verification
:crypto.verify(:eddsa, :none, message, signature, [pub, :ed25519])
# Returns: true | false
```

**Key detail**: `:crypto.sign` expects the **32-byte seed**, NOT the 64-byte `seed || pubkey` concatenation that Solana stores in keypair files.

## Solana Keypair Format

Solana's `~/.config/solana/id.json` is a JSON array of 64 decimal byte values:

```
[byte0, byte1, ..., byte63]
```

Layout: `<<seed::binary-32, pub::binary-32>>`

- Bytes 0-31: The Ed25519 seed (private key material)
- Bytes 32-63: The Ed25519 public key (= Solana address)

The Base58 encoding of the public key is the human-readable address.

## Implementation Plan

### `Signet.Solana.Keys`

```elixir
defmodule Signet.Solana.Keys do
  @moduledoc """
  Ed25519 keypair generation and management for Solana.
  """

  @type keypair :: {pub_key :: binary(), seed :: binary()}

  @doc "Generate a new random Ed25519 keypair."
  @spec generate_keypair() :: keypair()
  def generate_keypair()

  @doc "Derive public key from a 32-byte seed."
  @spec from_seed(binary()) :: keypair()
  def from_seed(seed) when byte_size(seed) == 32

  @doc "Import from a 64-byte Solana keypair (seed ++ pubkey)."
  @spec from_keypair_bytes(binary()) :: keypair()
  def from_keypair_bytes(bytes) when byte_size(bytes) == 64

  @doc "Import from a Solana JSON keypair file (list of 64 integers)."
  @spec from_json(String.t()) :: {:ok, keypair()} | {:error, term()}
  def from_json(json_string)

  @doc "Get the Base58-encoded Solana address from a public key."
  @spec to_address(binary()) :: String.t()
  def to_address(pub_key) when byte_size(pub_key) == 32
end
```

### `Signet.Solana.Signer` (GenServer)

The Solana signer follows the same GenServer + MFA backend pattern as the Ethereum `Signet.Signer`, but is much simpler: no recovery bit brute-force, no chain ID encoding.

```elixir
defmodule Signet.Solana.Signer do
  @moduledoc """
  GenServer that wraps Ed25519 signing backends for Solana.

  Delegates to a backend module via MFA (e.g., Signet.Solana.Signer.Ed25519
  for local keys, or Signet.Solana.Signer.CloudKMS for GCP KMS).

  Caches the public key (address) on first use.
  """
  use GenServer

  @doc "Start a named signer process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(mfa: mfa, name: name)

  @doc "Sign raw message bytes. Returns a 64-byte Ed25519 signature."
  @spec sign(binary(), GenServer.name()) :: {:ok, binary()} | {:error, term()}
  def sign(message, name \\ Signet.Solana.Signer.Default)

  @doc "Get the 32-byte public key (Solana address) for this signer."
  @spec address(GenServer.name()) :: binary()
  def address(name \\ Signet.Solana.Signer.Default)

  @doc "Verify an Ed25519 signature (standalone, no GenServer needed)."
  @spec verify(binary(), binary(), binary()) :: boolean()
  def verify(message, signature, pub_key)
end
```

Why a GenServer (same pattern as Ethereum):
1. **Caches the public key** - avoids re-deriving or re-fetching from KMS on every call
2. **Named process** - convenient for config-driven setup (`MySolSigner`)
3. **Unified interface** - same `sign/2` call regardless of whether the backend is a local key or KMS

What's simpler than the Ethereum GenServer:
- **No recovery bit**: Ed25519 signatures are deterministic, no brute-force needed
- **No chain ID encoding**: No EIP-155 equivalent
- **No `%Curvy.Signature{}` struct**: Backend returns raw 64-byte binary directly
- **`sign_direct/3`** is trivial: just `apply(mod, fun, [message] ++ args)`, return the result

### `Signet.Solana.Signer.Ed25519` (local key backend)

Analogous to `Signet.Signer.Curvy` for Ethereum.

```elixir
defmodule Signet.Solana.Signer.Ed25519 do
  @moduledoc """
  Ed25519 signing backend using a local private key seed.
  Uses OTP :crypto directly. Suitable for development and testing.
  """

  @doc "Get the public key for the given seed."
  @spec get_address(binary()) :: {:ok, binary()}
  def get_address(seed) when byte_size(seed) == 32

  @doc "Sign message bytes with the given seed."
  @spec sign(binary(), binary()) :: {:ok, binary()}
  def sign(message, seed) when byte_size(seed) == 32
end
```

### `Signet.Solana.Signer.CloudKMS` (GCP KMS backend)

Analogous to `Signet.Signer.CloudKMS` for Ethereum. GCP KMS supports Ed25519 since April 2024 (algorithm: `EC_SIGN_ED25519`).

```elixir
defmodule Signet.Solana.Signer.CloudKMS do
  @moduledoc """
  Ed25519 signing backend using Google Cloud KMS.
  Requires the `google_api_cloud_kms` optional dependency.
  """

  @doc "Get the Ed25519 public key from KMS."
  @spec get_address(term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, binary()} | {:error, term()}
  def get_address(cred, project, location, keychain, key, version)

  @doc "Sign message bytes using KMS."
  @spec sign(binary(), term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, binary()} | {:error, term()}
  def sign(message, cred, project, location, keychain, key, version)
end
```

#### How CloudKMS Ed25519 Differs from the Ethereum CloudKMS Signer

The existing `Signet.Signer.CloudKMS` (Ethereum/secp256k1) does three things differently:

| Aspect | Ethereum (`Signet.Signer.CloudKMS`) | Solana (`Signet.Solana.Signer.CloudKMS`) |
|---|---|---|
| **Algorithm** | `EC_SIGN_SECP256K1_SHA256` | `EC_SIGN_ED25519` |
| **Request body** | `%{digest: %{sha256: base64_keccak_hash}}` (pre-hashed) | `%{data: base64_raw_message}` (raw bytes, Ed25519 hashes internally) |
| **Public key PEM** | EC point: `{{:ECPoint, pubkey}, _} = pem_entry_decode(...)` then keccak → last 20 bytes | Ed25519 SubjectPublicKeyInfo (RFC 8410): 12-byte DER prefix + 32-byte raw pubkey |
| **Signature format** | DER-encoded ECDSA, parsed via `Curvy.Signature.parse/1` | Raw 64-byte Ed25519 signature, no parsing needed |
| **Post-processing** | Signer GenServer finds recovery bit, applies EIP-155 | None needed, signature is ready to use |

**PEM public key extraction** for Ed25519:
```elixir
# The PEM decodes to a 44-byte DER: 12-byte OID prefix + 32-byte raw pubkey
[pem_entry] = :public_key.pem_decode(pem)
{_type, der_bytes, _} = pem_entry
<<_prefix::binary-12, public_key::binary-32>> = der_bytes
```

The OID prefix is the ASN.1 encoding of `id-Ed25519` (OID 1.3.101.112) per RFC 8410.

**Signing request** for Ed25519:
```elixir
# Raw message bytes, base64-encoded (no keccak, no SHA-256)
message_enc = Base.encode64(message)

body: %{
  data: message_enc
}
```

The `data` field and `digest` field are mutually exclusive in the KMS API. Ed25519 keys MUST use `data` (raw bytes), not `digest`.

**Signature** comes back as a raw 64-byte value (base64-encoded in JSON), not DER:
```elixir
{:ok, signature} = Base.decode64(response.signature)
# signature is exactly 64 bytes, ready to use directly
```

#### Decision: Separate Module, Not Shared

We create a new `Signet.Solana.Signer.CloudKMS` rather than trying to generalize the existing `Signet.Signer.CloudKMS`. Reasons:

1. **Every step differs**: hashing, request field, PEM parsing, signature parsing. There's almost nothing to share.
2. **Return types differ**: Ethereum returns `{:ok, %Curvy.Signature{}}`, Solana returns `{:ok, <<_::512>>}`.
3. **The modules are small** (~40 lines each). Duplication of the KMS API call boilerplate is minimal and worth the clarity.
4. **Conditional compilation**: Both are wrapped in `if Code.ensure_loaded?(GoogleApi.CloudKMS.V1.Api.Projects)` since the dep is optional.

The one thing that IS shared is the KMS client connection setup (`Goth.fetch!/1` → `Connection.new/1`). If we want, we can extract that to a tiny helper, but it's 3 lines so probably not worth it.

## Test Plan

### RFC 8032 Test Vectors (Section 7.1)

**Test 1 - Empty message:**
```
seed:      9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60
pub:       d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a
message:   (empty)
signature: e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b
address:   FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z
```

**Test 2 - 1-byte message (`0x72`):**
```
seed:      4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb
pub:       3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c
message:   72
signature: 92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00
```

**Test 3 - 2-byte message (`0xaf82`):**
```
seed:      c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7
pub:       fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025
message:   af82
signature: 6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a
```

**Test SHA(abc) - 64-byte message:**
```
seed:      833fe62409237b9d62ec77587520911e9a759cec1d19755b7da901b96dca3d42
pub:       ec172b93ad5e563bf4932c70e1245034c35467ef2efd4d64ebf819683467e2bf
message:   ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
signature: dc2a4459e7369633a52b1bf277839a00201009a3efbf3ecb69bea2186c26b58909351fc9ac90b3ecfdfbc7c66431e0303dca179c138ac17ad9bef1177331a704
```

### Key Generation Tests

- `generate_keypair/0` returns `{pub, seed}` where `byte_size(pub) == 32` and `byte_size(seed) == 32`
- `from_seed/1` with the same seed always produces the same pubkey
- `from_seed/1` → `to_address/1` matches expected Base58 for known seeds

### Keypair Import Tests

- `from_keypair_bytes/1` correctly splits 64 bytes into seed + pubkey
- `from_keypair_bytes/1` validates that the pubkey matches the seed (derive and compare)
- `from_json/1` parses a Solana JSON keypair file

### Known Keypair Roundtrip

Using RFC 8032 Test 1:
```
seed → from_seed → {pub, seed} → to_address → "FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z"
```

Using all-zeros seed:
```
seed = <<0::256>>
pub  = 3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29
addr = "4zvwRjXUKGfvwnParsHAS3HuSVzV5cA4McphgmoCtajS"
```

### Signing Tests

- Sign + verify roundtrip for each RFC 8032 vector
- Signature is exactly 64 bytes
- Signing the same message with the same key always produces the same signature (Ed25519 is deterministic)
- Verification fails with wrong pubkey
- Verification fails with tampered message
- Verification fails with tampered signature

### Signer Configuration

Following the Ethereum pattern, Solana signers can be configured in `runtime.exs`:

```elixir
# Local key
config :signet, :solana_signer, [
  {MySolSigner, {:ed25519, System.get_env("SOLANA_PRIVATE_KEY")}}
]

# Cloud KMS
config :signet, :solana_signer, [
  {MySolSigner, {:cloud_kms, GCPCredentials, "projects/.../cryptoKeys/my-ed25519-key", "1"}}
]
```

`Signet.Application` would need a small addition to start Solana signers alongside Ethereum ones.

## Test Plan Additions (KMS)

### CloudKMS Tests

The existing `Signet.Signer.CloudKMS` tests (in `test/signer/cloud_kms_test.exs`) mock the GCP API. We'd follow the same pattern:

- Mock `asymmetricSign` → return base64-encoded 64-byte signature
- Mock `getPublicKey` → return Ed25519 PEM
- Verify the PEM extraction produces the correct 32-byte public key
- Verify the request body uses `data` (not `digest`)
- Verify the returned signature is the raw 64 bytes (not DER-parsed)

### Signer GenServer Tests

- Start signer with Ed25519 local backend, sign message, verify signature
- Start signer with mock KMS backend, sign message, verify signature
- Address is cached after first call
- Named process works (`MySolSigner`)

## File Layout

```
lib/signet/solana/keys.ex                # Signet.Solana.Keys
lib/signet/solana/signer.ex              # Signet.Solana.Signer (GenServer)
lib/signet/solana/signer/ed25519.ex      # Signet.Solana.Signer.Ed25519 (local key backend)
lib/signet/solana/signer/cloud_kms.ex    # Signet.Solana.Signer.CloudKMS (GCP KMS backend)
test/solana/keys_test.exs                # key tests
test/solana/signer_test.exs              # GenServer + Ed25519 backend tests
test/solana/signer/cloud_kms_test.exs    # KMS backend tests (mocked)
```

## Decisions

- **GenServer signer with MFA backends**: Same pattern as Ethereum's `Signet.Signer`, but simpler (no recovery bit, no chain ID). Caches public key, provides named process interface.
- **Separate CloudKMS module** (`Signet.Solana.Signer.CloudKMS`): Not a refactor of the Ethereum one. Every step differs (request field, hashing, PEM parsing, signature format). The modules are small enough that separate implementations are clearer than a shared abstraction.
- **No external dependency for core signing**: OTP `:crypto` handles Ed25519. CloudKMS uses the existing optional `google_api_cloud_kms` dep.
- **32-byte seed as the "private key"**: We use the 32-byte seed internally. The `from_keypair_bytes/1` and `from_json/1` functions handle the Solana 64-byte format.
- **Address = Base58(pubkey)**: No hashing step like Ethereum. The pubkey IS the address.
- **Backend returns raw binary**: Unlike Ethereum backends which return `%Curvy.Signature{}`, Solana backends return `{:ok, <<signature::binary-64>>}` directly. The GenServer passes it through with no post-processing.

## Open Questions

- **Should `Signet.Solana.Keys` validate the seed-to-pubkey relationship in `from_keypair_bytes/1`?** Yes - we should derive the pubkey from the seed and compare. A mismatched keypair would cause silent signing failures.
- **PEM extraction approach**: Should we use the binary prefix approach (`<<_::96, pub::binary-32>> = der`) or try OTP's `:public_key.pem_entry_decode/1` which may return `{:ed_pub, :ed25519, pub}` on OTP 25+? The binary approach is simpler and works across OTP versions. We should test both and pick the more robust one.
- **KMS key creation guidance**: Should we include instructions or a mix task for creating Ed25519 keys in GCP KMS? Nice-to-have but not critical for the library itself.

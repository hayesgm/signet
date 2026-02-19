# Phase 5: Integration & Polish

**Goal:** Bring the Solana support to release quality. Wire up application startup, clean up loose ends, update docs, bump version.

---

## 1. Application Startup: Solana Signers

`Signet.Application` currently only starts Ethereum signers from config. Add support for Solana signers:

```elixir
# runtime.exs
config :signet, :solana_signer, [
  {MySolSigner, {:ed25519, System.get_env("SOLANA_PRIVATE_KEY")}},
  # or
  {MySolKmsSigner, {:cloud_kms, GCPCredentials, "projects/.../cryptoKeys/my-key", "1"}}
]
```

Changes to `Signet.Application`:
- Read `:solana_signer` config alongside existing `:signer`
- Map `{:ed25519, key}` → `{Signet.Solana.Signer.Ed25519, :sign, [decoded_key]}`
- Map `{:cloud_kms, ...}` → `{Signet.Solana.Signer.CloudKMS, :sign, [...]}`
- Start `Signet.Solana.Signer` child specs with the mapped MFAs
- `:default` name maps to `Signet.Solana.Signer.Default`

## 2. SystemProgram: Use Programs Module

`Signet.Solana.SystemProgram` has its own `@system_program_id <<0::256>>` and `program_id/0`. Should delegate to `Signet.Solana.Programs.system_program/0` for consistency.

## 3. Elixir Version Bump

The `~B58[]` multi-character sigil requires Elixir >= 1.15. Currently `mix.exs` says `~> 1.13`. We should bump to `~> 1.15` (or document that `~B58` is only available on 1.15+, but since our own modules use it, we need the bump).

## 4. mix.exs Updates

- Description: "Lightweight Ethereum RPC client for Elixir" → mention Solana
- Version bump to 1.6.0 (Solana support is additive, nothing breaks). Save 2.0.0 for the Ethereum namespace migration (`Signet.RPC` → `Signet.Ethereum.RPC`) which is an actual breaking change.

## 5. README Updates

The README is entirely Ethereum-focused. Add a Solana section covering:

- **Solana Signing** - Ed25519 keypair generation, signing, verification
- **Solana RPC** - Configuration, basic calls (get_balance, get_slot, etc.)
- **Transactions** - Building and signing Solana transactions
- **Tokens** - SPL Token balance queries, transfers, ATA management
- **PDAs** - Program derived address derivation

Keep it concise - link to hexdocs for full API reference. Follow the existing README style (code examples with brief explanations).

## 6. Module Documentation Audit

Ensure every public module has:
- `@moduledoc` with clear description
- At least one `@doc` example on key functions
- `@spec` on all public functions

Quick audit of gaps:
- `Signet.Solana.RPC` - moduledoc exists, but individual method docs could use more examples
- `Signet.Solana.Token` - needs a concrete example in moduledoc showing a full balance query
- `Signet.Solana.Transaction` - moduledoc has a good example but could mention deserialization

## 7. Test Coverage Gaps

Review what's missing:
- **Programs module**: No dedicated test file. Add one that verifies all addresses encode to expected Base58 strings.
- **`get_token_accounts_by_owner` RPC method**: Added in Phase 4 but only tested indirectly through `Signet.Solana.Token`. Add direct RPC test.
- **`Signet.Solana.RPC` option propagation**: Test that commitment, encoding, and other options are actually sent in the request params (requires a smarter mock that captures params).

## 8. Compiler Warnings

Clean up any remaining warnings:
- Unused aliases in test files
- The `dispatch/2` clause ordering warning in the mock client

---

## Implementation Order

1. Clean up SystemProgram to use Programs module
2. Bump Elixir version in mix.exs
3. Wire up Solana signers in Application
4. Add missing tests (Programs, get_token_accounts_by_owner, option propagation)
5. Fix compiler warnings
6. Update mix.exs description and version
7. Update README with Solana section
8. Final pass: run full test suite, verify zero warnings

---

## Decisions

- **Version 1.6.0**: Solana support is additive and non-breaking. Save 2.0.0 for the Ethereum namespace migration which will actually break imports.
- **Elixir ~> 1.15**: Required for `~B58[]` sigil. Elixir 1.15 is 2+ years old at this point, reasonable minimum.
- **README stays concise**: Show the patterns, link to hexdocs for details. Don't try to document every function in the README.

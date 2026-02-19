# Phase 0: Base58 Encoding/Decoding

**Module:** `Signet.Base58`
**Dependencies:** None (pure Elixir)
**Prerequisite for:** Everything Solana (addresses, signatures, RPC responses)

---

## Overview

Solana uses Base58 (Bitcoin alphabet) for all human-readable representations of public keys and transaction signatures. This is the lowest-level building block we need.

**Not Base58Check**: Solana uses plain Base58, NOT Base58Check (no version prefix, no checksum). This is simpler than Bitcoin's usage.

## Alphabet

```
123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
```

Excluded characters: `0`, `O`, `I`, `l`, `+`, `/` (to avoid visual ambiguity).

## Algorithm

### Encoding (binary → string)

1. Count leading `0x00` bytes in the input. Each produces a `"1"` character.
2. Interpret remaining bytes as a big-endian unsigned integer.
3. Repeatedly `divmod` by 58, mapping remainders to the alphabet.
4. Prepend the leading `"1"` characters.

### Decoding (string → binary)

1. Count leading `"1"` characters. Each produces a `0x00` byte.
2. Map remaining characters to 0-57 values via the alphabet.
3. Accumulate: `acc = acc * 58 + char_value` for each character.
4. Convert accumulated integer to big-endian binary.
5. Prepend the leading zero bytes.

## Implementation Plan

```elixir
defmodule Signet.Base58 do
  @moduledoc """
  Base58 encoding and decoding using the Bitcoin/Solana alphabet.
  """

  # Tuple for O(1) index→char lookup
  @alphabet_tuple {?1, ?2, ...}  # all 58 chars

  # Map for O(1) char→index lookup
  @decode_map %{?1 => 0, ?2 => 1, ...}  # built from alphabet

  @spec encode(binary()) :: String.t()
  def encode(binary)

  @spec decode(String.t()) :: {:ok, binary()} | {:error, term()}
  def decode(string)

  @spec decode!(String.t()) :: binary()
  def decode!(string)  # raising variant
end
```

### Performance Notes

- The divmod approach is O(n^2) for n input bytes, but Solana's inputs are tiny (32 bytes for pubkeys, 64 for signatures). This takes microseconds.
- Use `elem(tuple, index)` for encode (O(1)) instead of `Enum.at(list, index)` (O(n)).
- Use `Map.fetch/2` for decode (O(1)) instead of `Enum.find_index/2` (O(n)).
- Accumulate encode output as a list, then `IO.iodata_to_binary/1` at the end to avoid repeated binary allocation.

## Test Plan

### IETF Draft Test Vectors (draft-msporny-base58-03)

| Hex Input | Base58 Output |
|-----------|---------------|
| `48656c6c6f20576f726c6421` | `2NEpo7TZRRrLZSi2U` |
| `54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f672e` | `USm3fpXnKG5EUBx2ndxBDMPVciP5hGey2Jh4NDv6gmeo1LkMeiKrLJUUBk6Z` |
| `0000287fb4cd` | `11233QC4` |

### Bitcoin Core Test Vectors

| Hex Input | Base58 Output |
|-----------|---------------|
| *(empty)* | *(empty)* |
| `61` | `2g` |
| `626262` | `a3gV` |
| `636363` | `aPEr` |
| `516b6fcd0f` | `ABnLTmg` |
| `bf4f89001e670274dd` | `3SEo3LWLoPntC` |
| `572e4794` | `3EFU7m` |
| `ecac89cad93923c02321` | `EJDM8drfXA6uyA` |
| `10c8511e` | `Rt5zm` |
| `00000000000000000000` | `1111111111` |
| `00eb15231dfceb60925886b67d065299925915aeb172c06647` | `1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L` |
| `000111d38e5fc9071ffcd20b4a763cc9ae4f252bb4e48fd66a835e252ada93ff480d6dd43dc62a641155a5` | `123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz` |

### Boundary Tests

| Hex Input | Base58 Output | Note |
|-----------|---------------|------|
| `271f359e` | `zzzzy` | Near rollover |
| `271f359f` | `zzzzz` | 58^5 - 1 |
| `271f35a0` | `211111` | 58^5 (carry) |

### Solana Address Tests

| Program | Base58 | Hex (32 bytes) |
|---------|--------|----------------|
| System Program | `11111111111111111111111111111111` | `00` x 32 |
| Token Program | `TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA` | `06ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9` |
| Associated Token Account | `ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL` | `8c97258f4e2489f1bb3d1029148e0d830b5a1399daff1084048e7bd8dbe9f859` |
| Token 2022 | `TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb` | `06ddf6e1ee758fde18425dbce46ccddab61afc4d83b90d27febdf928d8a18bfc` |

### Error Cases

- Invalid character in decode (e.g., `"0"`, `"O"`, `"I"`, `"l"`)
- Roundtrip: `decode(encode(x)) == x` for random binaries of various lengths

### Property Tests (if desired)

- For any binary `b`: `decode!(encode(b)) == b`
- For any valid Base58 string `s`: `encode(decode!(s)) == s`
- `byte_size(encode(b))` is approximately `byte_size(b) * 1.37`

## File Layout

```
lib/signet/base58.ex           # Signet.Base58
test/base58_test.exs           # tests
```

## Decisions

- **Module location**: `Signet.Base58` (top-level, not under `Signet.Solana`) since it's a generic encoding like `Signet.Hex`.
- **No external dependency**: The algorithm is ~40 lines and we avoid a dep.
- **API style**: Match existing Signet patterns. `encode/1` returns a string, `decode/1` returns `{:ok, binary} | {:error, term}`, `decode!/1` raises.

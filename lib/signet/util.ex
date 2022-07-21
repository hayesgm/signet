defmodule Signet.Util do
  defdelegate keccak(value), to: Signet.Hash

  @doc ~S"""
  Decodes a hex string, specifically requiring that the string begins
  with `0x` and allows mixed-case typing.

  ## Examples

    iex> Signet.Util.decode_hex("0x1122")
    {:ok, <<0x11, 0x22>>}

    iex> Signet.Util.decode_hex("0x1")
    {:ok, <<0x1>>}

    iex> Signet.Util.decode_hex("0xGG")
    :error
  """
  def decode_hex("0x" <> hex) do
    hex_padded =
      if rem(byte_size(hex), 2) == 1 do
        "0" <> hex
      else
        hex
      end

    Base.decode16(hex_padded, case: :mixed)
  end

  def decode_hex!(hex) do
    {:ok, result} = decode_hex(hex)
    result
  end

  @doc ~S"""
  Decodes hex, allowing it to either by "0x..." or <<1::160>>.

  Note: a hex-printed string, in this case, must start with 0x,
        otherwise it will be interpreted as its ASCII values.

  ## Examples

      iex> Signet.Util.decode_hex_input!("0x55")
      <<0x55>>

      iex> Signet.Util.decode_hex_input!(<<0x55>>)
      <<0x55>>
  """
  def decode_hex_input!(hex = "0x" <> _), do: decode_hex!(hex)
  def decode_hex_input!(hex) when is_binary(hex), do: hex

  @doc ~S"""
  Encodes a hex string, adding a `0x` prefix.

  Note: if `short` is set, then any leading zeros will be stripped.

  ## Examples

    iex> Signet.Util.encode_hex(<<0x11, 0x22>>)
    "0x1122"

    iex> Signet.Util.encode_hex(<<0xc>>)
    "0x0C"

    iex> Signet.Util.encode_hex(<<0xc>>, true)
    "0xC"

    iex> Signet.Util.encode_hex(<<0x0>>, true)
    "0x0"
  """
  def encode_hex(hex, short \\ false)
  def encode_hex(nil, _short), do: nil

  def encode_hex(hex, short) when is_binary(hex) do
    enc = Base.encode16(hex)

    "0x" <>
      if short do
        case String.replace_leading(enc, "0", "") do
          "" ->
            "0"

          els ->
            els
        end
      else
        enc
      end
  end

  def encode_hex(v, short) when is_integer(v), do: encode_hex(:binary.encode_unsigned(v), short)

  @doc ~S"""
  Encodes a number as a binary representation of a certain number of
  bytes.

  ## Examples

    iex> Signet.Util.encode_bytes(257, 4)
    <<0, 0, 1, 1>>

    iex> Signet.Util.encode_bytes(nil, 4)
    nil
  """
  def encode_bytes(nil, _), do: nil

  def encode_bytes(b, size) do
    pad(:binary.encode_unsigned(b), size)
  end

  @doc ~S"""
  Pads a binary to a given length

  ## Examples

    iex> Signet.Util.pad(<<1, 2>>, 2)
    <<1, 2>>

    iex> Signet.Util.pad(<<1, 2>>, 4)
    <<0, 0, 1, 2>>

    iex> Signet.Util.pad(<<1, 2>>, 1)
    ** (FunctionClauseError) no function clause matching in Signet.Util.pad/2
  """
  def pad(bin, size) when size > byte_size(bin) do
    padding_len_bits = (size - byte_size(bin)) * 8
    <<0::size(padding_len_bits)>> <> bin
  end

  def pad(bin, size) when size == byte_size(bin), do: bin

  @doc ~S"""
  Returns an Ethereum address from a given DER-encoded public key.

  ## Examples

    iex> public_key = Signet.Util.decode_hex!("0x0422")
    iex> Signet.Util.get_eth_address(public_key) |> Signet.Util.encode_hex()
    "0x759F1AFDC24ABA433A3E18B683F8C04A6EAA69F0"
  """
  def get_eth_address(public_key) do
    <<4, public_key_raw::binary>> = public_key
    <<_::bitstring-size(96), address::bitstring-size(160)>> = keccak(public_key_raw)

    address
  end

  @doc ~S"""
  Converts a number to wei, possibly from gwei, etc.

  ## Examples

      iex> Signet.Util.to_wei(100)
      100

      iex> Signet.Util.to_wei({100, :gwei})
      100000000000
  """
  @spec to_wei(integer() | {integer, :gwei}) :: number()
  def to_wei(amount) when is_integer(amount), do: amount
  def to_wei({amount, :wei}) when is_integer(amount), do: amount
  def to_wei({amount, :gwei}) when is_integer(amount), do: amount * 1_000_000_000

  @chains %{
    mainnet: 1,
    ropsten: 2,
    rinkeby: 4,
    goerli: 5,
    kovan: 42
  }

  @doc ~S"""
  Parses a chain id, which can be given as an integer or an atom of a known network.

  ## Examples

      iex> Signet.Util.parse_chain_id(5)
      5

      iex> Signet.Util.parse_chain_id(:goerli)
      5
  """
  def parse_chain_id(chain_id) when is_atom(chain_id), do: Map.fetch!(@chains, chain_id)
  def parse_chain_id(chain_id) when is_integer(chain_id), do: chain_id

  @doc ~S"""
  Checksums an Ethereum address per [EIP-55](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-55.md),
  the result is a string-encoded version of the address.

  ## Examples

      iex> Signet.Util.checksum_address("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
      "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"

      iex> Signet.Util.checksum_address("0xFB6916095CA1DF60BB79CE92CE3EA74C37C5D359")
      "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"

      iex> Signet.Util.checksum_address("0xdbf03b407c01e7cd3cbea99509d93f8dddc8c6fb")
      "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB"

      iex> Signet.Util.checksum_address("0xd1220a0cf47c7b9be7a2e6ba89f429762e7b9adb")
      "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb"
  """
  def checksum_address(address = "0x" <> _), do: checksum_address(decode_hex!(address))

  def checksum_address(address) when is_binary(address) and byte_size(address) == 20 do
    # Weirdly instead of keccaking the address, we keccak the string representation...
    "0x" <> address_enc = encode_hex(address)
    hash = Signet.Hash.keccak(String.downcase(address_enc))

    # Use a charlist to semi-quickly get the correct hex digit
    lower = '0123456789abcdef'
    upper = '0123456789ABCDEF'

    res =
      for {nibble, hash_val} <- Enum.zip(nibbles(address), nibbles(hash)), into: [] do
        casing = if hash_val >= 8, do: upper, else: lower
        Enum.at(casing, nibble)
      end

    "0x" <> to_string(res)
  end

  @doc ~S"""
  Returns the nibbles of a binary as a list.

  ## Examples

      iex> Signet.Util.nibbles(<<0xF5,0xE6,0xD0>>)
      [0xF, 0x5, 0xE, 0x6, 0xD, 0x0]
  """
  def nibbles(v) do
    Enum.reverse(do_nibbles(v, []))
  end

  defp do_nibbles(<<>>, acc), do: acc

  defp do_nibbles(<<high::4, low::4, rest::binary()>>, acc),
    do: do_nibbles(rest, [low, high | acc])
end

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
end

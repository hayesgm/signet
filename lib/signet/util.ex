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
  @spec decode_hex(String.t()) :: {:ok, binary()} | :error
  @deprecated "Use Signet.Hex.decode_hex/1 instead"
  def decode_hex("0x" <> hex) do
    hex_padded =
      if rem(byte_size(hex), 2) == 1 do
        "0" <> hex
      else
        hex
      end

    Base.decode16(hex_padded, case: :mixed)
  end

  @doc ~S"""
  Decodes a hex string, specifically requiring that the string begins
  with `0x` and allows mixed-case typing.

  Similar to `decode_hex/1`, but raises on error

  ## Examples

    iex> Signet.Util.decode_hex!("0x1122")
    <<0x11, 0x22>>

    iex> Signet.Util.decode_hex!("0x1")
    <<0x1>>

    iex> Signet.Util.decode_hex!("0xGG")
    ** (RuntimeError) invalid hex
  """
  @spec decode_hex!(String.t()) :: binary() | no_return()
  @deprecated "Use Signet.Hex.decode_hex!/1 instead"
  def decode_hex!(hex) do
    case decode_hex(hex) do
      {:ok, result} ->
        result

      _ ->
        raise "invalid hex"
    end
  end

  @doc ~S"""
  Decodes hex but requires the result be a given set of bytes, or
  otherwise raises.

  ## Examples

    iex> Signet.Util.decode_sized_hex!("0x1122", 2)
    <<0x11, 0x22>>

    iex> Signet.Util.decode_sized_hex!("0x1122", 3)
    ** (RuntimeError) mismatch byte size. expected 3, got: 2

    iex> Signet.Util.decode_sized_hex!("0xGG", 3)
    ** (RuntimeError) invalid hex
  """
  @spec decode_sized_hex!(String.t(), integer()) :: binary() | no_return()
  @deprecated "Use Signet.Hex.decode_sized!/2 instead"
  def decode_sized_hex!(hex, size) do
    result = decode_hex!(hex)

    if byte_size(result) == size do
      result
    else
      raise "mismatch byte size. expected #{size}, got: #{byte_size(result)}"
    end
  end

  @doc ~S"""
  Decodes hex if the size is exactly one 32-byte word, otherwise raises.

  ## Examples

    iex> Signet.Util.decode_word!("0x00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff")
    <<0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff,0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff>>

    iex> Signet.Util.decode_word!("0x1122")
    ** (RuntimeError) mismatch byte size. expected 32, got: 2
  """
  @spec decode_word!(String.t()) :: <<_::256>> | no_return()
  @deprecated "Use Signet.Hex.decode_word!/2 instead"
  def decode_word!(hex), do: decode_sized_hex!(hex, 32)

  @doc ~S"""
  Decodes hex if the size is exactly one 20-byte address, otherwise raises.

  ## Examples

    iex> Signet.Util.decode_address!("0x00112233445566778899aabbccddeeff00112233")
    <<0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff,0x00,0x11,0x22,0x33>>

    iex> Signet.Util.decode_address!("0x1122")
    ** (RuntimeError) mismatch byte size. expected 20, got: 2
  """
  @spec decode_address!(String.t()) :: <<_::160>> | no_return()
  @deprecated "Use Signet.Hex.decode_address!/2 instead"
  def decode_address!(hex), do: decode_sized_hex!(hex, 20)

  @doc ~S"""
  Decodes hex to an integer.

  ## Examples

    iex> Signet.Util.decode_hex_number!("0x11223344")
    0x11223344
  """
  @spec decode_hex_number!(String.t()) :: integer() | no_return()
  @deprecated "Use Signet.Hex.decode_hex_number!/2 instead"
  def decode_hex_number!(hex), do: decode_hex!(hex) |> :binary.decode_unsigned()

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
  def decode_hex_input!(hex = "0x" <> _), do: Signet.Hex.decode_hex!(hex)
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
  @deprecated "Use Signet.Hex.encode_short_hex/1 instead"
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

    iex> use Signet.Hex
    iex> public_key = ~h[0x0422]
    iex> Signet.Util.get_eth_address(public_key)
    ...> |> Signet.Hex.encode_hex()
    "0x759f1afdc24aba433a3e18b683f8c04a6eaa69f0"
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
    kovan: 42,
    base: 8453,
    base_sepolia: 84532,
    arbitrum: 42161,
    arbitrum_sepolia: 421_614,
    mumbai: 80001,
    sepolia: 11_155_111,
    optimism: 10,
    optimism_sepolia: 11_155_420,
    world_chain: 480,
    world_chain_sepolia: 4801,
    unichain: 130,
    avalanche: 43_114,
    bnb_smart_chain: 56,
    hyper_evm: 999,
    lens: 232,
    polygon: 137,
    sonic: 146,
    ink: 57073,
    plume: 98866
  }

  @doc ~S"""
  Parses a chain id, which can be given as an integer or an atom of a known network.

  ## Examples

      iex> Signet.Util.parse_chain_id(5)
      5

      iex> Signet.Util.parse_chain_id(:unichain)
      130
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
    lower = ~c"0123456789abcdef"
    upper = ~c"0123456789ABCDEF"

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

  defp do_nibbles(<<high::4, low::4, rest::binary>>, acc),
    do: do_nibbles(rest, [low, high | acc])

  defmodule RecoveryBit do
    @moduledoc """
    There are a number of ways to look at recovery bits. Either:

    * `:base`: In the range `{0,1}`, which are the outputs of a signer library
    * `:ethereum`: In the range `{27,28}`, as defined in the yellow paper
    * `:eip155`: In the range `{35+chain_id*2,35+chain_id*2+1}`, as defined in EIP-155

    This module provides tools between switching through these choices.
    """

    @rec_types [:base, :ethereum, :eip155]
    @type rec_type() :: :base | :ethereum | :eip155

    @doc """
    Normalizes a binary-encoded signature to the given requested type,
    i.e. `:base`, `:ethereum`, or `:eip155`.

    ## Examples

        iex> Signet.Util.RecoveryBit.normalize(28, :eip155)
        46

        iex> Signet.Util.RecoveryBit.normalize(1, :ethereum)
        28

        iex> Signet.Util.RecoveryBit.normalize(45, :base)
        0
    """
    @spec normalize(non_neg_integer(), rec_type()) :: non_neg_integer() | :no_return
    def normalize(recovery_bit, rec_type \\ :eip155) when rec_type in @rec_types do
      base = recover_base(recovery_bit)

      case rec_type do
        :base ->
          base

        :ethereum ->
          base + 27

        :eip155 ->
          35 + Signet.Application.chain_id() * 2 + base
      end
    end

    @doc """
    Normalizes a binary-encoded signature to the given requested type,
    i.e. `:base`, `:ethereum`, or `:eip155`.

    ## Examples

        iex> Signet.Util.RecoveryBit.normalize_signature(<<1::256, 2::256, 28>>, :eip155)
        <<1::256, 2::256, 46>>

        iex> Signet.Util.RecoveryBit.normalize_signature(<<1::256, 2::256, 1>>, :ethereum)
        <<1::256, 2::256, 28>>

        iex> Signet.Util.RecoveryBit.normalize_signature(<<1::256, 2::256, 45>>, :base)
        <<1::256, 2::256, 0>>
    """
    @spec normalize_signature(Signet.signature(), rec_type()) :: Signet.signature() | :no_return
    def normalize_signature(<<rs::binary-size(64), v>>, rec_type \\ :eip155)
        when rec_type in @rec_types do
      v_normalized = normalize(v, rec_type)

      <<rs::binary-size(64), v_normalized::8>>
    end

    @doc """
    Normalizes a recovery bit to be either 0 or 1.

    ## Examples

        iex> Signet.Util.RecoveryBit.recover_base(0)
        0

        iex> Signet.Util.RecoveryBit.recover_base(1)
        1

        iex> Signet.Util.RecoveryBit.recover_base(27)
        0

        iex> Signet.Util.RecoveryBit.recover_base(28)
        1

        iex> Signet.Util.RecoveryBit.recover_base(45)
        0

        iex> Signet.Util.RecoveryBit.recover_base(46)
        1

        iex> Signet.Util.RecoveryBit.recover_base(47)
        ** (RuntimeError) Invalid EIP-155 Signature: recovery_bit=47, chain_id=5

        iex> Signet.Util.RecoveryBit.recover_base(2)
        ** (FunctionClauseError) no function clause matching in Signet.Util.RecoveryBit.recover_base/1
    """
    @spec recover_base(non_neg_integer()) :: 0 | 1 | no_return()
    def recover_base(v) when v in [0, 1], do: v
    def recover_base(v) when v in [27, 28], do: v - 27

    def recover_base(v) when v >= 35 do
      case v - Signet.Application.chain_id() * 2 - 35 do
        base when base in [0, 1] ->
          base

        _ ->
          raise "Invalid EIP-155 Signature: recovery_bit=#{v}, chain_id=#{Signet.Application.chain_id()}"
      end
    end
  end

  @doc false
  def nil_map(nil, _), do: nil
  def nil_map(x, fun), do: fun.(x)

  @doc """
  Normalizes the result of a `Finch` request.

  Any non-2xx status codes are wrapped in {:error, _}.
  Other Finch errors abstract away the details of Finch.
  """
  def normalize_finch_result(finch_result) do
    case finch_result do
      {:ok, %Finch.Response{status: code} = resp} when code >= 200 and code < 300 ->
        {:ok, resp}

      {:ok, %Finch.Response{status: _} = resp} ->
        {:error, resp}

      {:error, %Finch.Error{reason: reason}} ->
        {:error, "[Signet] HTTP client error: #{inspect(reason)}"}

      {:error, _ = error} ->
        {:error, "[Signet] Unknown error: #{inspect(error)}"}
    end
  end
end

defmodule Signet.Base58 do
  @moduledoc """
  Base58 encoding and decoding using the Bitcoin/Solana alphabet.

  This is plain Base58, NOT Base58Check (no version prefix or checksum).
  Used by Solana for public keys (addresses) and transaction signatures.

  If you `use Signet.Base58`, you get the `~B58` sigil for compile-time
  Base58-to-binary decoding.

  ## Examples

      iex> Signet.Base58.encode(<<0, 0, 0>>)
      "111"

      iex> Signet.Base58.encode(<<0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x57, 0x6f, 0x72, 0x6c, 0x64, 0x21>>)
      "2NEpo7TZRRrLZSi2U"

      iex> Signet.Base58.decode("2NEpo7TZRRrLZSi2U")
      {:ok, "Hello World!"}

      iex> Signet.Base58.decode("abc0def")
      {:error, {:invalid_character, "0"}}
  """

  defmacro __using__(_opts) do
    quote do
      require Signet.Base58
      import Signet.Base58, only: [sigil_B58: 2]
    end
  end

  @doc ~S"""
  Handles the sigil `~B58` for compile-time Base58 decoding.

  Decodes a Base58 string to binary at compile time, raising on
  invalid input. Uses uppercase `B58` because Elixir multi-character
  sigils require uppercase letters.

  ## Examples

      iex> use Signet.Base58
      iex> ~B58[11111111111111111111111111111111]
      <<0::256>>

      iex> use Signet.Base58
      iex> ~B58[TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA]
      <<6, 221, 246, 225, 215, 101, 161, 147, 217, 203, 225, 70, 206, 235, 121, 172, 28, 180, 133, 237, 95, 91, 55, 145, 58, 140, 245, 133, 126, 255, 0, 169>>
  """
  defmacro sigil_B58(term, _modifiers)

  defmacro sigil_B58({:<<>>, _meta, [string]}, _modifiers) when is_binary(string) do
    Signet.Base58.decode!(string)
  end

  @alphabet ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  # O(1) index → char lookup
  @alphabet_tuple List.to_tuple(@alphabet)

  # O(1) char → index lookup
  @decode_map (for {char, idx} <- Enum.with_index(@alphabet), into: %{}, do: {char, idx})

  @doc """
  Encode a binary to a Base58 string.

  Each leading zero byte in the input produces a `"1"` character in the output.

  ## Examples

      iex> Signet.Base58.encode(<<>>)
      ""

      iex> Signet.Base58.encode(<<0>>)
      "1"

      iex> Signet.Base58.encode(<<0x61>>)
      "2g"
  """
  @spec encode(binary()) :: String.t()
  def encode(<<>>), do: ""

  def encode(binary) when is_binary(binary) do
    leading = count_leading_zeros(binary, 0)
    prefix = String.duplicate("1", leading)

    case :binary.decode_unsigned(binary) do
      0 -> prefix
      n -> prefix <> encode_int(n, [])
    end
  end

  defp encode_int(0, acc), do: IO.iodata_to_binary(acc)

  defp encode_int(n, acc) do
    encode_int(div(n, 58), [elem(@alphabet_tuple, rem(n, 58)) | acc])
  end

  defp count_leading_zeros(<<0, rest::binary>>, n), do: count_leading_zeros(rest, n + 1)
  defp count_leading_zeros(_, n), do: n

  @doc """
  Decode a Base58 string to a binary.

  Returns `{:ok, binary}` on success, or `{:error, {:invalid_character, char}}` if the
  string contains characters outside the Base58 alphabet.

  ## Examples

      iex> Signet.Base58.decode("")
      {:ok, <<>>}

      iex> Signet.Base58.decode("1")
      {:ok, <<0>>}

      iex> Signet.Base58.decode("2g")
      {:ok, <<0x61>>}
  """
  @spec decode(String.t()) :: {:ok, binary()} | {:error, {:invalid_character, String.t()}}
  def decode(<<>>), do: {:ok, <<>>}

  def decode(string) when is_binary(string) do
    {leading, rest} = count_leading_ones(string, 0)
    prefix = :binary.copy(<<0>>, leading)

    case decode_chars(rest, 0) do
      {:ok, 0} -> {:ok, prefix}
      {:ok, n} -> {:ok, prefix <> :binary.encode_unsigned(n)}
      error -> error
    end
  end

  @doc """
  Decode a Base58 string to a binary, raising on invalid input.

  ## Examples

      iex> Signet.Base58.decode!("2g")
      <<0x61>>
  """
  @spec decode!(String.t()) :: binary()
  def decode!(string) do
    case decode(string) do
      {:ok, binary} -> binary
      {:error, reason} -> raise ArgumentError, "invalid Base58: #{inspect(reason)}"
    end
  end

  defp count_leading_ones(<<"1", rest::binary>>, n), do: count_leading_ones(rest, n + 1)
  defp count_leading_ones(rest, n), do: {n, rest}

  defp decode_chars(<<>>, acc), do: {:ok, acc}

  defp decode_chars(<<c, rest::binary>>, acc) do
    case Map.fetch(@decode_map, c) do
      {:ok, val} -> decode_chars(rest, acc * 58 + val)
      :error -> {:error, {:invalid_character, <<c>>}}
    end
  end
end

defmodule Signet.Hash do
  @doc ~S"""
  Returns the keccak of the given binary message.

  ## Examples

    iex> use Signet.Hex
    iex> Signet.Hash.keccak("test")
    ~h[0x9C22FF5F21F0B81B113E63F7DB6DA94FEDEF11B2119B4088B89664FB9A3CB658]
  """
  def keccak(message), do: ExSha3.keccak_256(message)

  @doc ~S"""
  Returns the keccak of the given binary message, as an unsigned.

  ## Examples

    iex> Signet.Hash.keccak_unsigned("test")
    70622639689279718371527342103894932928233838121221666359043189029713682937432
  """
  def keccak_unsigned(message) do
    message
    |> keccak()
    |> :binary.decode_unsigned()
  end
end

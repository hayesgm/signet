defmodule Signet.Hash do
  @doc ~S"""
  Returns the keccak of the given binary message.

  ## Examples

    iex> Signet.Hash.keccak("test")
    <<156, 34, 255, 95, 33, 240, 184, 27, 17, 62, 99, 247, 219, 109, 169, 79, 237, 239, 17, 178, 17, 155, 64, 136, 184, 150, 100, 251, 154, 60, 182, 88>>
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

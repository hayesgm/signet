defmodule Signet.Keys do
  @moduledoc """
  Signet library to generate Ethereum key pairs.
  """

  @doc """
  Generates a new keypair as an `{eth_address, private_key}`.

  ## Examples

      iex> {address, priv_key} = Signet.Keys.generate_keypair()
      iex> {byte_size(address), byte_size(priv_key)}
      {20, 32}
  """
  def generate_keypair() do
    {<<4, pub_key::binary-size(64)>>, <<priv_key::binary-size(32)>>} =
      :crypto.generate_key(:ecdh, :secp256k1)

    <<_::96, address::binary-size(20)>> = Signet.Hash.keccak(pub_key)

    {address, priv_key}
  end
end

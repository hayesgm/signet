defmodule Signet.Signer.Curvy do
  @moduledoc """
  Signer to sign messages using a private key directly.

  Note: this should not be used in production systems. Please see `Signet.Signer.CloudKMS`.
  """
  import Signet.Hash, only: [keccak: 1]

  @doc ~S"""
  Get the Ethereum address associated with the given private key.

  ## Examples

      iex> priv_key = "800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf" |> Base.decode16!(case: :mixed)
      iex> {:ok, address} = Signet.Signer.Curvy.get_address(priv_key)
      iex> Signet.Hex.to_address(address)
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec get_address(binary()) :: {:ok, binary()} | {:error, String.t()}
  def get_address(private_key) do
    private_key
    |> Curvy.Key.from_privkey()
    |> Curvy.Key.to_pubkey(compressed: false)
    |> Signet.Util.get_eth_address()
    |> ok!()
  end

  @doc ~S"""
  Signs the given message using the private key, after digesting the message with keccak.

  ## Examples

      iex> use Signet.Hex
      iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
      iex> {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
      iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7])
      iex> Signet.Recover.recover_eth("test", %{sig|recid: recid}) |> Signet.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec sign(String.t(), binary()) :: {:ok, Curvy.Signature.t()} | {:error, String.t()}
  def sign(message, private_key) when is_binary(message) do
    sign_digest(keccak(message), private_key)
  end

  @doc ~S"""
  Signs the given message which was already digested.

  ## Examples

      iex> use Signet.Hex
      iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
      iex> message_hash = ~h[0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658]
      iex> {:ok, sig} = Signet.Signer.Curvy.sign_digest(message_hash, priv_key)
      iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7])
      iex> Signet.Recover.recover_eth("test", %{sig|recid: recid}) |> Signet.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec sign_digest(String.t(), binary()) :: {:ok, Curvy.Signature.t()} | {:error, String.t()}
  def sign_digest(message_hash, private_key) when is_binary(message_hash) do
    priv_key = Curvy.Key.from_privkey(private_key)

    Curvy.sign(message_hash, priv_key, hash: :keccak)
    |> Curvy.Signature.parse()
    |> ok!()
  end

  defp ok!(v), do: {:ok, v}
end

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
      iex> Base.encode16(address)
      "63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"
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

      iex> priv_key = Base.decode16!("800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf", case: :mixed)
      iex> {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
      iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, Base.decode16!("63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"))
      iex> Signet.Recover.recover_eth("test", %{sig|recid: recid}) |> Base.encode16()
      "63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"
  """
  @spec sign(String.t(), binary()) :: {:ok, Curvy.Signature.t()} | {:error, String.t()}
  def sign(message, private_key) when is_binary(message) do
    priv_key = Curvy.Key.from_privkey(private_key)

    message_hash = keccak(message)

    Curvy.sign(message_hash, priv_key, hash: :keccak)
    |> Curvy.Signature.parse()
    |> ok!()
  end

  defp ok!(v), do: {:ok, v}
end

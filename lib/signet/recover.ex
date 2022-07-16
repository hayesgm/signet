defmodule Signet.Recover do
  import Signet.Hash, only: [keccak: 1]
  import Signet.Util, only: [get_eth_address: 1, decode_hex: 1, encode_hex: 1]

  defp decode_signature(s = %Curvy.Signature{}), do: s

  defp decode_signature(signature = "0x" <> _signature_hex) do
    with {:ok, signature_bytes} <- decode_hex(signature) do
      decode_signature(signature_bytes)
    end
  end

  defp decode_signature(<<r::integer-size(256), s::integer-size(256), v::integer-size(8)>>),
    do: %Curvy.Signature{
      crv: :secp256k1,
      r: r,
      s: s,
      recid: rem(v + 1, 2)
    }


  @doc """
  Prefixes a message with "Etheruem Signed Message" prefix, as per
  [EIP-191](https://eips.ethereum.org/EIPS/eip-191).

  ## Examples

    iex> Signet.Recover.prefix_eth("hello")
    "\x19Ethereum Signed Message:\\n5hello"
  """
  def prefix_eth(msg), do: "\x19Ethereum Signed Message:\n" <> to_string(String.length(msg)) <> msg

  @doc """
  Recovers a signer's public key from a signed message. The message will be
  digested by keccak first. Note: the rec_id can be embeded in the signature
  or passed separately.

  ## Examples

    iex> priv_key = Base.decode16!("800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf", case: :mixed)
    iex> {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, Base.decode16!("63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"))
    iex> Signet.Recover.recover_public_key("test", %{sig|recid: recid}) |> Base.encode16()
    "0480076BFB96955526052B2676DFCA87E0B7869CE85E00C5DBCE29E76B8429D6DBF0F33B1A0095B2A9A4D9EA2A9746B122995A5B5874EE3161138C9D19F072B2D9"
  """
  def recover_public_key(message, signature) do
    signature
    |> decode_signature()
    |> Curvy.recover_key(keccak(message), hash: :keccak)
    |> Curvy.Key.to_pubkey(compressed: false)
  end

  @doc """
  Recovers a signer's Ethereum address from a signed message. The message will
  be digested by keccak first. Note: the rec_id can be embeded in the signature
  or passed separately.

  ## Examples

    iex> priv_key = Base.decode16!("800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf", case: :mixed)
    iex> {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, Base.decode16!("63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"))
    iex> Signet.Recover.recover_eth("test", %{sig|recid: recid}) |> Base.encode16()
    "63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"
  """
  def recover_eth(message, signature) do
    message
    |> recover_public_key(signature)
    |> get_eth_address()
  end

  @doc """
  Finds the given recid which recovers the given signature for the message to the given
  Ethereum address. This is a very simple guess-check-revise since there are only four
  possible values, and we only accept two of those.

  ## Examples

    iex> priv_key = Base.decode16!("800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf", case: :mixed)
    iex> {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, Base.decode16!("63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"))
    iex> Signet.Recover.recover_eth("test", %{sig|recid: recid}) |> Base.encode16()
    "63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"
  """
  def find_recid(message, signature, address) do
    recid =
      Enum.find(0..3, fn recid ->
        Signet.Recover.recover_eth(message, %{signature | recid: recid}) == address
      end)

    case recid do
      nil ->
        {:error, "unable to recover to address #{encode_hex(address)}"}

      x when x > 1 ->
        {:error, "too high recovery bit #{recid}"}

      _ ->
        {:ok, recid}
    end
  end
end

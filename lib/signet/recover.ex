defmodule Signet.Recover do
  use Signet.Hex

  import Signet.Hash, only: [keccak: 1]
  import Signet.Util, only: [get_eth_address: 1]

  defp decode_signature(s = %Curvy.Signature{}), do: s

  defp decode_signature(signature = "0x" <> _signature_hex) do
    with {:ok, signature_bytes} <- Hex.decode_hex(signature) do
      decode_signature(signature_bytes)
    end
  end

  defp decode_signature(<<r::integer-size(256), s::integer-size(256), v::integer-size(8)>>),
    do: %Curvy.Signature{
      crv: :secp256k1,
      r: r,
      s: s,
      recid:
        if v in [0, 1] do
          v
        else
          rem(v + 1, 2)
        end
    }

  @doc """
  Prefixes a message with "Etheruem Signed Message" prefix, as per
  [EIP-191](https://eips.ethereum.org/EIPS/eip-191).

  ## Examples

    iex> Signet.Recover.prefix_eth("hello")
    "\x19Ethereum Signed Message:\\n5hello"
  """
  def prefix_eth(msg),
    do: "\x19Ethereum Signed Message:\n" <> to_string(String.length(msg)) <> msg

  @doc """
  Recovers a signer's public key from a signed message. The message will be
  digested by keccak first. Note: the rec_id can be embeded in the signature
  or passed separately.

  ## Examples

    iex> use Signet.Hex
    iex> # Decoded Signature
    iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
    iex> {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7])
    iex> Signet.Recover.recover_public_key("test", %{sig|recid: recid}) |> to_hex()
    "0x0480076bfb96955526052b2676dfca87e0b7869ce85e00c5dbce29e76b8429d6dbf0f33b1a0095b2a9a4d9ea2a9746b122995a5b5874ee3161138c9d19f072b2d9"

    iex> use Signet.Hex
    iex> # Binary Signature
    iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
    iex> {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7])
    iex> signature = <<sig.r::256, sig.s::256, recid>>
    iex> Signet.Recover.recover_public_key("test", signature) |> to_hex()
    "0x0480076bfb96955526052b2676dfca87e0b7869ce85e00c5dbce29e76b8429d6dbf0f33b1a0095b2a9a4d9ea2a9746b122995a5b5874ee3161138c9d19f072b2d9"

    iex> use Signet.Hex
    iex> # EIP-155 Signature
    iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
    iex> {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7])
    iex> recovery_bit = 35 + 5 * 2 + recid
    iex> signature = <<sig.r::256, sig.s::256, recovery_bit::8>>
    iex> Signet.Recover.recover_public_key("test", signature) |> to_hex()
    "0x0480076bfb96955526052b2676dfca87e0b7869ce85e00c5dbce29e76b8429d6dbf0f33b1a0095b2a9a4d9ea2a9746b122995a5b5874ee3161138c9d19f072b2d9"
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

    iex> use Signet.Hex
    iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
    iex> {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7])
    iex> Signet.Recover.recover_eth("test", %{sig|recid: recid})
    ...> |> to_hex()
    "0x63cc7c25e0cdb121abb0fe477a6b9901889f99a7"
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

    iex> use Signet.Hex
    iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
    iex> {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
    iex> {:ok, recid} = Signet.Recover.find_recid("test", sig, ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7])
    iex> Signet.Recover.recover_eth("test", %{sig|recid: recid})
    ...> |> to_hex()
    "0x63cc7c25e0cdb121abb0fe477a6b9901889f99a7"
  """
  def find_recid(message, signature, address) do
    recid =
      Enum.find(0..3, fn recid ->
        Signet.Recover.recover_eth(message, %{signature | recid: recid}) == address
      end)

    case recid do
      nil ->
        {:error, "unable to recover to address #{Hex.encode_hex(address)}"}

      x when x > 1 ->
        {:error, "too high recovery bit #{recid}"}

      _ ->
        {:ok, recid}
    end
  end
end

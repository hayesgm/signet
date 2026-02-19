defmodule Signet.Solana.Signer.Ed25519 do
  @moduledoc """
  Ed25519 signing backend using a local private key seed.

  Uses OTP `:crypto` directly (available since OTP 24). This is the Solana
  equivalent of `Signet.Signer.Curvy` for Ethereum.

  ## Examples

      iex> seed = Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")
      iex> {:ok, sig} = Signet.Solana.Signer.Ed25519.sign("hello", seed)
      iex> byte_size(sig)
      64
  """

  @doc """
  Get the 32-byte Ed25519 public key for the given seed.

  ## Examples

      iex> seed = Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")
      iex> {:ok, pub} = Signet.Solana.Signer.Ed25519.get_address(seed)
      iex> Base.encode16(pub, case: :lower)
      "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  """
  @spec get_address(<<_::256>>) :: {:ok, <<_::256>>}
  def get_address(<<seed::binary-32>>) do
    {pub, _seed} = :crypto.generate_key(:eddsa, :ed25519, seed)
    {:ok, pub}
  end

  @doc """
  Sign message bytes with the given 32-byte seed.

  Ed25519 handles hashing internally (SHA-512), so the message is signed
  as raw bytes with no external digest step.

  Returns `{:ok, signature}` where signature is exactly 64 bytes.

  ## Examples

      iex> seed = Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")
      iex> {:ok, sig} = Signet.Solana.Signer.Ed25519.sign(<<>>, seed)
      iex> Base.encode16(sig, case: :lower)
      "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
  """
  @spec sign(binary(), <<_::256>>) :: {:ok, <<_::512>>}
  def sign(message, <<seed::binary-32>>) when is_binary(message) do
    signature = :crypto.sign(:eddsa, :none, message, [seed, :ed25519])
    {:ok, signature}
  end
end

defmodule Signet.Solana.Keys do
  @moduledoc """
  Ed25519 keypair generation and management for Solana.

  Solana uses Ed25519 public keys as addresses directly (no hashing).
  A keypair consists of a 32-byte seed (private key material) and a
  32-byte public key. Solana stores these as a 64-byte concatenation
  (seed ++ pubkey) in keypair files.

  ## Examples

      iex> {pub, seed} = Signet.Solana.Keys.generate_keypair()
      iex> {byte_size(pub), byte_size(seed)}
      {32, 32}

      iex> {pub, _seed} = Signet.Solana.Keys.from_seed(<<0::256>>)
      iex> Signet.Solana.Keys.to_address(pub)
      "4zvwRjXUKGfvwnParsHAS3HuSVzV5cA4McphgmoCtajS"
  """

  @type keypair :: {pub_key :: <<_::256>>, seed :: <<_::256>>}

  @doc """
  Generate a new random Ed25519 keypair.

  Returns `{pub_key, seed}` where both are 32-byte binaries.

  ## Examples

      iex> {pub, seed} = Signet.Solana.Keys.generate_keypair()
      iex> byte_size(pub) == 32 and byte_size(seed) == 32
      true
  """
  @spec generate_keypair() :: keypair()
  def generate_keypair do
    {pub, seed} = :crypto.generate_key(:eddsa, :ed25519)
    {pub, seed}
  end

  @doc """
  Derive a keypair from a 32-byte Ed25519 seed.

  Deterministic: the same seed always produces the same public key.

  ## Examples

      iex> seed = Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")
      iex> {pub, ^seed} = Signet.Solana.Keys.from_seed(seed)
      iex> Base.encode16(pub, case: :lower)
      "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  """
  @spec from_seed(<<_::256>>) :: keypair()
  def from_seed(<<seed::binary-32>>) do
    {pub, ^seed} = :crypto.generate_key(:eddsa, :ed25519, seed)
    {pub, seed}
  end

  @doc """
  Import a keypair from the 64-byte Solana format (seed ++ pubkey).

  Validates that the public key matches the seed by re-deriving it.

  ## Examples

      iex> seed = Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")
      iex> pub = Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")
      iex> {:ok, {^pub, ^seed}} = Signet.Solana.Keys.from_keypair_bytes(seed <> pub)
      iex> byte_size(pub)
      32
  """
  @spec from_keypair_bytes(<<_::512>>) :: {:ok, keypair()} | {:error, :pubkey_mismatch}
  def from_keypair_bytes(<<seed::binary-32, claimed_pub::binary-32>>) do
    {derived_pub, ^seed} = :crypto.generate_key(:eddsa, :ed25519, seed)

    if derived_pub == claimed_pub do
      {:ok, {derived_pub, seed}}
    else
      {:error, :pubkey_mismatch}
    end
  end

  @doc """
  Import a keypair from a Solana JSON keypair file.

  Solana keypair files (e.g. `~/.config/solana/id.json`) contain a JSON
  array of 64 decimal byte values: the first 32 bytes are the seed and
  the last 32 bytes are the public key.

  ## Examples

      iex> json = "[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,59,106,39,188,206,182,164,45,98,163,168,208,42,111,13,115,101,50,21,119,29,226,67,166,58,192,72,161,139,89,218,41]"
      iex> {:ok, {pub, _seed}} = Signet.Solana.Keys.from_json(json)
      iex> Signet.Solana.Keys.to_address(pub)
      "4zvwRjXUKGfvwnParsHAS3HuSVzV5cA4McphgmoCtajS"
  """
  @spec from_json(String.t()) :: {:ok, keypair()} | {:error, term()}
  def from_json(json_string) do
    with {:ok, bytes} when is_list(bytes) <- Jason.decode(json_string),
         true <- length(bytes) == 64,
         keypair_bytes <- :binary.list_to_bin(bytes) do
      from_keypair_bytes(keypair_bytes)
    else
      false -> {:error, :invalid_length}
      {:error, _} = err -> err
    end
  end

  @doc """
  Get the Base58-encoded Solana address from a 32-byte public key.

  In Solana, the public key IS the address (no hashing step).

  ## Examples

      iex> pub = Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")
      iex> Signet.Solana.Keys.to_address(pub)
      "FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z"
  """
  @spec to_address(<<_::256>>) :: String.t()
  def to_address(<<pub_key::binary-32>>) do
    Signet.Base58.encode(pub_key)
  end
end

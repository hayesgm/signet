defmodule Signet.Solana.Signer do
  @moduledoc """
  GenServer that wraps Ed25519 signing backends for Solana.

  Follows the same MFA (module, function, args) backend pattern as the
  Ethereum `Signet.Signer`, but much simpler: no recovery bit brute-force,
  no chain ID encoding.

  Delegates to a backend module (e.g., `Signet.Solana.Signer.Ed25519` for
  local keys, or `Signet.Solana.Signer.CloudKMS` for GCP KMS). Caches
  the public key on first use.

  ## Examples

      # Start via supervisor or manually:
      {:ok, pid} = Signet.Solana.Signer.start_link(
        mfa: {Signet.Solana.Signer.Ed25519, :sign, [seed]},
        name: MySolSigner
      )

      # Sign a message:
      {:ok, signature} = Signet.Solana.Signer.sign(message, MySolSigner)

      # Get the signer's public key:
      pub_key = Signet.Solana.Signer.address(MySolSigner)
  """
  use GenServer

  require Logger

  @doc """
  Starts a new Solana signer process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    mfa = Keyword.fetch!(opts, :mfa)
    name = Keyword.fetch!(opts, :name)
    Logger.info("Starting Signet.Solana.Signer #{inspect(name)}...")
    GenServer.start_link(__MODULE__, %{mfa: mfa, name: name}, name: name)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @doc """
  Sign raw message bytes. Returns a 64-byte Ed25519 signature.

  ## Examples

      iex> signer = Signet.Solana.Test.Signer.start_signer()
      iex> {:ok, sig} = Signet.Solana.Signer.sign("test", signer)
      iex> byte_size(sig)
      64
  """
  @spec sign(binary(), GenServer.name()) :: {:ok, <<_::512>>} | {:error, term()}
  def sign(message, name \\ Signet.Solana.Signer.Default) when is_binary(message) do
    GenServer.call(name, {:sign, message})
  end

  @doc """
  Get the 32-byte public key (Solana address) for this signer.

  ## Examples

      iex> signer = Signet.Solana.Test.Signer.start_signer()
      iex> address = Signet.Solana.Signer.address(signer)
      iex> byte_size(address)
      32
  """
  @spec address(GenServer.name()) :: <<_::256>>
  def address(name \\ Signet.Solana.Signer.Default) do
    GenServer.call(name, :get_address)
  end

  @doc """
  Verify an Ed25519 signature. Standalone function, no GenServer needed.

  ## Examples

      iex> seed = Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")
      iex> pub = Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")
      iex> {:ok, sig} = Signet.Solana.Signer.Ed25519.sign("test", seed)
      iex> Signet.Solana.Signer.verify("test", sig, pub)
      true
  """
  @spec verify(binary(), <<_::512>>, <<_::256>>) :: boolean()
  def verify(message, <<signature::binary-64>>, <<pub_key::binary-32>>)
      when is_binary(message) do
    :crypto.verify(:eddsa, :none, message, signature, [pub_key, :ed25519])
  end

  # --- GenServer callbacks ---

  @impl true
  def handle_call({:sign, message}, _from, state = %{mfa: mfa}) do
    {:reply, sign_direct(message, mfa), state}
  end

  def handle_call(:get_address, _from, state = %{address: address}) do
    {:reply, address, state}
  end

  def handle_call(:get_address, _from, state = %{name: name, mfa: {mod, _fun, args}}) do
    {:ok, address} = apply(mod, :get_address, args)

    Logger.info(
      "Signet.Solana.Signer #{inspect(name)} address: #{Signet.Solana.Keys.to_address(address)}"
    )

    {:reply, address, Map.put(state, :address, address)}
  end

  defp sign_direct(message, {mod, fun, args}) do
    apply(mod, fun, [message | args])
  end
end

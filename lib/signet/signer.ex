defmodule Signet.Signer do
  @doc """
  Signet.Signer is a GenServer which can sign messages. This module takes an
  mfa (mod, func, args triple) which defines how to actually sign messages.
  For instance, `Signet.Signer.Curvy` will sign with a public key, or
  `Signet.Signer.CloudKMS` will sign using a GCP Cloud KMS key. In either
  case, the caller should start the GenServer, and then call:
  `Signet.Signer.sign(MySigner, "message")`. This should return back a
  properly signed message.

  Note: we also enforce that a given signer process knows its public key,
  such that we can verify signatures recovery bits. That is, since CloudKMS
  and other signing tools don't return a recovery bit, necessary for Ethereum,
  we test all 4 possible bits to make sure a signature recovers to the correct
  signer address, but we need to know what that address should be to accomplish
  this task.

  Additionally, chain_id is used to return EIP-155 compliant signatures.
  """
  use GenServer
  require Logger
  import Signet.Util, only: [encode_bytes: 2, encode_hex: 1]

  @doc """
  Starts a new Signet.Signer process.
  """
  def start_link(mfa: mfa, name: name) do
    Logger.info("Starting Signet.Signer #{name}...")
    chain_id = Signet.Application.chain_id()

    GenServer.start_link(
      __MODULE__,
      %{mfa: mfa, name: name, chain_id: chain_id},
      name: name
    )
  end

  @doc """
  Initializes a new Signet.Signer.
  """
  @impl true
  def init(state) do
    {:ok, state}
  end

  @doc """
  Signs a message using this signing key.

  ## Examples

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, sig} = Signet.Signer.sign("test", signer_proc)
      iex> Signet.Recover.recover_eth("test", sig) |> Base.encode16()
      "63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, <<_r::256, _s::256, v::binary>>} = Signet.Signer.sign("test", signer_proc, chain_id: 0x05f5e0ff)
      iex> :binary.decode_unsigned(v)
      0x05f5e0ff * 2 + 35 + 1
  """
  def sign(message, name \\ Signet.Signer.Default, opts \\ []) do
    chain_id = Keyword.get(opts, :chain_id, GenServer.call(name, :get_chain_id))
    GenServer.call(name, {:sign, {message, chain_id}})
  end

  @doc """
  Gets the address for this signer.

  ## Examples

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> Signet.Signer.address(signer_proc) |> Base.encode16()
      "63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"
  """
  def address(name \\ Signet.Signer.Default) do
    GenServer.call(name, :get_address)
  end

  @doc """
  Gets the chain id for this signer.

  ## Examples

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> Signet.Signer.chain_id(signer_proc)
      5
  """
  def chain_id(name \\ Signet.Signer.Default) do
    GenServer.call(name, :get_chain_id)
  end

  @doc """
  Handles signing a message. Finds and memoizes address on first call. Address
  is required for finding recovery bit.
  """
  @impl true
  def handle_call(
        {:sign, {message, chain_id}},
        _from,
        state = %{address: address, mfa: mfa}
      ) do
    {:reply, sign_direct(message, address, mfa, chain_id), state}
  end

  # Note absence of address in state, find it and set it and then sign. Address will be cached on next signing.
  def handle_call(
    {:sign, {message, chain_id}},
        _from,
        state = %{name: name, mfa: {mod, _fn, args} = mfa}
      ) do
    {:ok, address} = apply(mod, :get_address, args)
    Logger.info("Signet.Signer #{name} signing with address #{encode_hex(address)}")

    {:reply, sign_direct(message, address, mfa, chain_id), Map.put(state, :address, address)}
  end

  # Reads address from state, or finds and memoize address on first call.
  def handle_call(:get_address, _from, state = %{address: address}) do
    {:reply, address, state}
  end

  def handle_call(:get_address, _from, state = %{name: name, mfa: {mod, _fn, args}}) do
    {:ok, address} = apply(mod, :get_address, args)
    Logger.info("Signet.Signer #{name} signing with address #{encode_hex(address)}")
    {:reply, address, Map.put(state, :address, address)}
  end

  def handle_call(:get_chain_id, _from, state = %{chain_id: chain_id}) do
    {:reply, chain_id, state}
  end

  @doc """
  Directly sign a message, not using a signer process.

  This is mostly used internally, but can be used safely externally as well.
  """
  @spec sign_direct(String.t(), binary(), mfa(), integer()) ::
          {:ok, binary()} | {:error, String.t()}
  def sign_direct(message, address, {mod, fun, args}, chain_id_or_name) do
    with {:ok,
          signature = %Curvy.Signature{
            crv: :secp256k1,
            r: r,
            recid: nil,
            s: s
          }} <- apply(mod, fun, [message] ++ args),
         {:ok, recid} <- Signet.Recover.find_recid(message, signature, address) do
      # EIP-155
      chain_id = Signet.Util.parse_chain_id(chain_id_or_name)
      v = if chain_id == 0, do: 27 + recid, else: chain_id * 2 + 35 + recid

      {:ok, encode_bytes(r, 32) <> encode_bytes(s, 32) <> :binary.encode_unsigned(v)}
    end
  end
end

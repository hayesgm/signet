defmodule Signet.Transaction do
  @moduledoc """
  A module to help build, sign and encode Ethereum transactions.
  """

  defmodule V1 do
    @moduledoc """
    Represents a V1 or "Legacy" (that is, pre-EIP-1559) transaction.
    """

    defstruct [
      :nonce,
      :gas_price,
      :gas_limit,
      :to,
      :value,
      :data,
      :v,
      :r,
      :s
    ]

    @doc ~S"""
    Constructs a new V1 (Legacy) Ethereum transaction.

    ## Examples

        iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        %Signet.Transaction.V1{
          nonce: 1,
          gas_price: 100000000000,
          gas_limit: 100000,
          to: <<1::160>>,
          value: 2,
          data: <<1, 2, 3>>,
          v: 42,
          r: 0,
          s: 0
        }
    """
    def new(nonce, gas_price, gas_limit, to, value, data, chain_id \\ nil) do
      %__MODULE__{
        nonce: nonce,
        gas_price: if(!is_nil(gas_price), do: Signet.Util.to_wei(gas_price), else: nil),
        gas_limit: gas_limit,
        to: to,
        value: Signet.Util.to_wei(value),
        data: data,
        v:
          if(is_nil(chain_id),
            do: Signet.Application.chain_id(),
            else: Signet.Util.parse_chain_id(chain_id)
          ),
        r: 0,
        s: 0
      }
    end

    @doc ~S"""
    Build an RLP-encoded transaction. Note: transactions can be encoded before they are signed, which
    uses `[chain_id, 0, 0]` in the signature fields, otherwise those fields are `[v, r, s]`.

    ## Examples

        iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Signet.Transaction.V1.encode()
        ...> |> Base.encode16()
        "E80185174876E800830186A094000000000000000000000000000000000000000102830102032A8080"
    """
    def encode(%__MODULE__{
          nonce: nonce,
          gas_price: gas_price,
          gas_limit: gas_limit,
          to: to,
          value: value,
          data: data,
          v: v,
          r: r,
          s: s
        }) do
      ExRLP.encode([nonce, gas_price, gas_limit, to, value, data, v, r, s])
    end

    @doc ~S"""
    Decode an RLP-encoded transaction.

    ## Examples

        iex> "E80185174876E800830186A094000000000000000000000000000000000000000102830102032A8080"
        ...> |> Base.decode16!()
        ...> |> Signet.Transaction.V1.decode()
        {:ok, %Signet.Transaction.V1{
          nonce: 1,
          gas_price: 100000000000,
          gas_limit: 100000,
          to: <<1::160>>,
          value: 2,
          data: <<1, 2, 3>>,
          v: 42,
          r: 0,
          s: 0
        }}
    """
    def decode(trx_enc) do
      case ExRLP.decode(trx_enc) do
        [nonce, gas_price, gas_limit, to, value, data, v, r, s] ->
          {:ok,
           %__MODULE__{
             nonce: :binary.decode_unsigned(nonce),
             gas_price: :binary.decode_unsigned(gas_price),
             gas_limit: :binary.decode_unsigned(gas_limit),
             to: to,
             value: :binary.decode_unsigned(value),
             data: data,
             v: :binary.decode_unsigned(v),
             r: :binary.decode_unsigned(r),
             s: :binary.decode_unsigned(s)
           }}

        _ ->
          {:error, "invalid legacy transaction"}
      end
    end

    @doc ~S"""
    Adds a signature to a transaction. This overwrites the `[chain_id, 0, 0]` fields, as per EIP-155.

    ## Examples

        iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Signet.Transaction.V1.add_signature(<<1::256, 2::256, 3::8>>)
        %Signet.Transaction.V1{
          nonce: 1,
          gas_price: 100000000000,
          gas_limit: 100000,
          to: <<1::160>>,
          value: 2,
          data: <<1, 2, 3>>,
          v: 3,
          r: <<1::256>>,
          s: <<2::256>>
        }
    """
    def add_signature(
          transaction = %__MODULE__{},
          <<r::binary-size(32), s::binary-size(32), v::integer-size(8)>>
        ) do
      %{transaction | v: v, r: r, s: s}
    end

    @doc ~S"""
    Recovers a signature from a transaction, if it's been signed. Otherwise returns an error.

    ## Examples

        iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Signet.Transaction.V1.add_signature(<<1::256, 2::256, 3::8>>)
        ...> |> Signet.Transaction.V1.get_signature()
        {:ok, <<1::256, 2::256, 3::8>>}

        iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Signet.Transaction.V1.get_signature()
        {:error, "transaction missing signature"}
    """
    def get_signature(%__MODULE__{v: _v, r: 0, s: 0}),
      do: {:error, "transaction missing signature"}

    def get_signature(%__MODULE__{v: v, r: r, s: s}) do
      {:ok, <<r::binary-size(32), s::binary-size(32), v::8>>}
    end

    @doc ~S"""
    Recovers the signer from a given transaction, if it's been signed.

    ## Examples

        iex> {:ok, address} =
        ...> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Signet.Transaction.V1.add_signature(<<1::256, 2::256, 3::8>>)
        ...> |> Signet.Transaction.V1.recover_signer(:kovan)
        ...> Base.encode16(address)
        "47643AC1194D7E8C6D04DD631D456137028BBC1F"

        iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Signet.Transaction.V1.recover_signer(:kovan)
        {:error, "transaction missing signature"}
    """
    def recover_signer(transaction, chain_id) do
      trx_encoded = encode(%{transaction | v: Signet.Util.parse_chain_id(chain_id), r: 0, s: 0})

      with {:ok, signature} <- get_signature(transaction) do
        {:ok, Signet.Recover.recover_eth(trx_encoded, signature)}
      end
    end
  end

  @doc """
  Builds a v1-style call to a given contract

  ## Examples

      iex> Signet.Transaction.build_trx(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, 100_000, 0, 5)
      %Signet.Transaction.V1{
        nonce: 5,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<1::160>>,
        value: 0,
        data: Base.decode16!("A291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001"),
        v: 5,
        r: 0,
        s: 0
      }

      iex> call_data = Base.decode16!("A291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001")
      ...> Signet.Transaction.build_trx(<<1::160>>, 5, call_data, {50, :gwei}, 100_000, 0, 5)
      %Signet.Transaction.V1{
        nonce: 5,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<1::160>>,
        value: 0,
        data: Base.decode16!("A291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001"),
        v: 5,
        r: 0,
        s: 0
      }
  """
  def build_trx(address, nonce, call_data, gas_price, gas_limit, value, chain_id \\ nil) do
    data =
      case call_data do
        {abi, params} ->
          ABI.encode(abi, params)

        call_data when is_binary(call_data) ->
          call_data
      end

    V1.new(nonce, gas_price, gas_limit, address, value, data, chain_id)
  end

  @doc ~S"""
  Builds and signs a transaction, to be ready to be passed to JSON-RPC.

  Optionally takes a callback to modify the transaction before it is signed.

  ## Examples

      iex> signer_proc = SignetHelper.start_signer()
      iex> {:ok, signed_trx} = Signet.Transaction.build_signed_trx(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, 100_000, 0, signer: signer_proc, chain_id: :goerli)
      iex> {:ok, signer} = Signet.Transaction.V1.recover_signer(signed_trx, 5)
      iex> Base.encode16(signer)
      "63CC7C25E0CDB121ABB0FE477A6B9901889F99A7"
  """
  def build_signed_trx(
        address,
        nonce,
        call_data,
        gas_price,
        gas_limit,
        value,
        opts \\ []
      ) do
    signer = Keyword.get(opts, :signer, Signet.Signer.Default)
    chain_id = Keyword.get(opts, :chain_id, nil)
    callback = Keyword.get(opts, :callback, nil)

    transaction = build_trx(address, nonce, call_data, gas_price, gas_limit, value, chain_id)
    callback = if(is_nil(callback), do: fn trx -> {:ok, trx} end, else: callback)

    with {:ok, transaction} <- callback.(transaction),
         transaction_encoded <- V1.encode(transaction),
         {:ok, signature} <- Signet.Signer.sign(transaction_encoded, signer) do
      {:ok, V1.add_signature(transaction, signature)}
    end
  end

  # TODO: Add v2 transactions
  # def sign_transaction(transaction = %V1{}) do
  # end

  # defmodule V2 do
  #   defstruct [
  #     :chain_id,
  #     :nonce,
  #     :max_priority_fee_per_gas,
  #     :max_fee_per_gas,
  #     :gas_limit,
  #     :destination,
  #     :amount,
  #     :data,
  #     :access_list,
  #     :signature_y_parity,
  #     :signature_r,
  #     :signature_s
  #   ]

  #   @spec encode(t()) :: binary()
  #   def encode(transaction=%__MODULE__{}) do
  #     rlp([
  #       transaction.chain_id,
  #       transaction.nonce,
  #       transaction.max_priority_fee_per_gas,
  #       transaction.max_fee_per_gas,
  #       transaction.gas_limit,
  #       transaction.destination,
  #       transaction.amount,
  #       transaction.data,
  #       transaction.access_list,
  #     ])
  #   end
  # end
end

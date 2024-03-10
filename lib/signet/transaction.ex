defmodule Signet.Transaction do
  @moduledoc """
  A module to help build, sign and encode Ethereum transactions.
  """

  defmodule V1 do
    @moduledoc """
    Represents a V1 or "Legacy" (that is, pre-EIP-1559) transaction.
    """

    @type t :: %__MODULE__{
            nonce: integer(),
            gas_price: integer(),
            gas_limit: integer(),
            to: <<_::160>>,
            value: integer(),
            data: binary(),
            v: integer(),
            r: integer(),
            s: integer()
          }

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

        iex> use Signet.Hex
        iex> ~h[0xE80185174876E800830186A094000000000000000000000000000000000000000102830102032A8080]
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
          <<r::binary-size(32), s::binary-size(32), v::binary>>
        ) do
      %{transaction | v: :binary.decode_unsigned(v), r: r, s: s}
    end

    @doc ~S"""
    Recovers a signature from a transaction, if it's been signed. Otherwise returns an error.

    ## Examples

        iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Signet.Transaction.V1.add_signature(<<1::256, 2::256, 3::8>>)
        ...> |> Signet.Transaction.V1.get_signature()
        {:ok, <<1::256, 2::256, 3::8>>}

        iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Signet.Transaction.V1.add_signature(<<1::256, 2::256, 0x05f5e0ff::32>>)
        ...> |> Signet.Transaction.V1.get_signature()
        {:ok, <<1::256, 2::256, 0x05f5e0ff::32>>}

        iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Signet.Transaction.V1.get_signature()
        {:error, "transaction missing signature"}
    """
    def get_signature(%__MODULE__{v: _v, r: 0, s: 0}),
      do: {:error, "transaction missing signature"}

    def get_signature(%__MODULE__{v: v, r: r, s: s}) do
      v_enc = :binary.encode_unsigned(v)
      {:ok, <<r::binary-size(32), s::binary-size(32), v_enc::binary>>}
    end

    @doc ~S"""
    Recovers the signer from a given transaction, if it's been signed.

    ## Examples

        iex> {:ok, address} =
        ...> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
        ...> |> Signet.Transaction.V1.add_signature(<<1::256, 2::256, 3::8>>)
        ...> |> Signet.Transaction.V1.recover_signer(:kovan)
        ...> Signet.Hex.to_address(address)
        "0x47643AC1194d7e8C6d04dD631D456137028bBc1F"

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

  defmodule V2 do
    @moduledoc """
    Represents a V2 or EIP-1559 transaction.
    """

    @type t :: %__MODULE__{
            chain_id: integer(),
            nonce: integer(),
            max_priority_fee_per_gas: integer(),
            max_fee_per_gas: integer(),
            gas_limit: integer(),
            destination: <<_::160>>,
            amount: integer(),
            data: binary(),
            access_list: [<<_::160>>],
            signature_y_parity: boolean(),
            signature_r: <<_::256>>,
            signature_s: <<_::256>>
          }

    defstruct [
      :chain_id,
      :nonce,
      :max_priority_fee_per_gas,
      :max_fee_per_gas,
      :gas_limit,
      :destination,
      :amount,
      :data,
      :access_list,
      :signature_y_parity,
      :signature_r,
      :signature_s
    ]

    @doc ~S"""
    Constructs a new V2 (EIP-1559) Ethereum transaction.

    ## Examples

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
        %Signet.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [<<2::160>>, <<3::160>>],
          signature_y_parity: nil,
          signature_r: nil,
          signature_s: nil
        }

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], true, <<0x01::256>>, <<0x02::256>>, :goerli)
        %Signet.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [<<2::160>>, <<3::160>>],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }
    """
    def new(
          nonce,
          max_priority_fee_per_gas,
          max_fee_per_gas,
          gas_limit,
          destination,
          amount,
          data,
          access_list,
          chain_id \\ nil
        ),
        do:
          new(
            nonce,
            max_priority_fee_per_gas,
            max_fee_per_gas,
            gas_limit,
            destination,
            amount,
            data,
            access_list,
            nil,
            nil,
            nil,
            chain_id
          )

    def new(
          nonce,
          max_priority_fee_per_gas,
          max_fee_per_gas,
          gas_limit,
          destination,
          amount,
          data,
          access_list,
          signature_y_parity,
          signature_r,
          signature_s,
          chain_id \\ nil
        ) do
      %__MODULE__{
        chain_id:
          if(is_nil(chain_id),
            do: Signet.Application.chain_id(),
            else: Signet.Util.parse_chain_id(chain_id)
          ),
        nonce: nonce,
        max_priority_fee_per_gas:
          if(!is_nil(max_priority_fee_per_gas),
            do: Signet.Util.to_wei(max_priority_fee_per_gas),
            else: nil
          ),
        max_fee_per_gas:
          if(!is_nil(max_fee_per_gas), do: Signet.Util.to_wei(max_fee_per_gas), else: nil),
        gas_limit: gas_limit,
        destination: destination,
        amount: Signet.Util.to_wei(amount),
        data: data,
        access_list: access_list,
        signature_y_parity: signature_y_parity,
        signature_r: signature_r,
        signature_s: signature_s
      }
    end

    @doc ~S"""
    Build an RLP-encoded transaction. Note: if the transaction does not have a signature
    set (that is, `signature_y_parity`, `signature_r` or `signature_s` are `nil`), then
    we will encode a partial transaction (which can be used for signing).

    ## Examples

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
        ...> |> Signet.Transaction.V2.encode()
        ...> |> Signet.Hex.to_hex()
        "0x02f8560501843b9aca0085174876e800830186a09400000000000000000000000000000000000000010283010203ea940000000000000000000000000000000000000002940000000000000000000000000000000000000003"

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], true, <<0x01::256>>, <<0x02::256>>, :goerli)
        ...> |> Signet.Transaction.V2.encode()
        ...> |> Signet.Hex.to_hex()
        "0x02f8990501843b9aca0085174876e800830186a09400000000000000000000000000000000000000010283010203ea94000000000000000000000000000000000000000294000000000000000000000000000000000000000301a00000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000000000000000000000000000000000000000000002"
    """
    def encode(%__MODULE__{
          chain_id: chain_id,
          nonce: nonce,
          max_priority_fee_per_gas: max_priority_fee_per_gas,
          max_fee_per_gas: max_fee_per_gas,
          gas_limit: gas_limit,
          destination: destination,
          amount: amount,
          data: data,
          access_list: access_list,
          signature_y_parity: signature_y_parity,
          signature_r: signature_r,
          signature_s: signature_s
        })
        when is_nil(signature_y_parity) or is_nil(signature_r) or is_nil(signature_s) do
      <<0x02>> <>
        ExRLP.encode([
          chain_id,
          nonce,
          max_priority_fee_per_gas,
          max_fee_per_gas,
          gas_limit,
          destination,
          amount,
          data,
          access_list
        ])
    end

    def encode(%__MODULE__{
          chain_id: chain_id,
          nonce: nonce,
          max_priority_fee_per_gas: max_priority_fee_per_gas,
          max_fee_per_gas: max_fee_per_gas,
          gas_limit: gas_limit,
          destination: destination,
          amount: amount,
          data: data,
          access_list: access_list,
          signature_y_parity: signature_y_parity,
          signature_r: signature_r,
          signature_s: signature_s
        }) do
      <<0x02>> <>
        ExRLP.encode([
          chain_id,
          nonce,
          max_priority_fee_per_gas,
          max_fee_per_gas,
          gas_limit,
          destination,
          amount,
          data,
          access_list,
          if(signature_y_parity, do: 1, else: 0),
          signature_r,
          signature_s
        ])
    end

    @doc ~S"""
    Decode an RLP-encoded transaction. Note: the signature must have been
    signed (i.e. properly encoded), not simply encoded for signing.

    ## Examples

        iex> use Signet.Hex
        iex> Signet.Transaction.V2.decode(~h[0x02F8990501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203EA94000000000000000000000000000000000000000294000000000000000000000000000000000000000301A00000000000000000000000000000000000000000000000000000000000000001A00000000000000000000000000000000000000000000000000000000000000002])
        {:ok, %Signet.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [<<2::160>>, <<3::160>>],
          signature_y_parity: true,
          signature_r: 0x01,
          signature_s: 0x02
        }}
    """
    def decode(<<0x02, trx_enc::binary>>) do
      case ExRLP.decode(trx_enc) do
        [
          chain_id,
          nonce,
          max_priority_fee_per_gas,
          max_fee_per_gas,
          gas_limit,
          destination,
          amount,
          data,
          access_list,
          signature_y_parity,
          signature_r,
          signature_s
        ] ->
          {:ok,
           %__MODULE__{
             chain_id: :binary.decode_unsigned(chain_id),
             nonce: :binary.decode_unsigned(nonce),
             max_priority_fee_per_gas: :binary.decode_unsigned(max_priority_fee_per_gas),
             max_fee_per_gas: :binary.decode_unsigned(max_fee_per_gas),
             gas_limit: :binary.decode_unsigned(gas_limit),
             destination: destination,
             amount: :binary.decode_unsigned(amount),
             data: data,
             access_list: access_list,
             signature_y_parity: :binary.decode_unsigned(signature_y_parity) == 1,
             signature_r: :binary.decode_unsigned(signature_r),
             signature_s: :binary.decode_unsigned(signature_s)
           }}

        _ ->
          {:error, "invalid v2 transaction"}
      end
    end

    @doc ~S"""
    Adds a signature to a transaction. This overwrites the `signature_y_parity`, `signature_r` and `signature_s` fields.

    ## Examples

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], 1, 0x01, 0x02, :goerli)
        ...> |> Signet.Transaction.V2.add_signature(true, <<1::256>>, <<2::256>>)
        %Signet.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [<<2::160>>, <<3::160>>],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], 1, 0x01, 0x02, :goerli)
        ...> |> Signet.Transaction.V2.add_signature(<<1::256, 2::256, 1::8>>)
        %Signet.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [<<2::160>>, <<3::160>>],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], 1, 0x01, 0x02, :goerli)
        ...> |> Signet.Transaction.V2.add_signature(<<1::256, 2::256, 27::8>>)
        %Signet.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [<<2::160>>, <<3::160>>],
          signature_y_parity: false,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], 1, 0x01, 0x02, :goerli)
        ...> |> Signet.Transaction.V2.add_signature(<<1::256, 2::256, 38::8>>)
        %Signet.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [<<2::160>>, <<3::160>>],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], 1, 0x01, 0x02, :goerli)
        ...> |> Signet.Transaction.V2.add_signature(<<1::256, 2::256, 3838::16>>)
        %Signet.Transaction.V2{
          chain_id: 5,
          nonce: 1,
          max_priority_fee_per_gas: 1000000000,
          max_fee_per_gas: 100000000000,
          gas_limit: 100000,
          destination: <<1::160>>,
          amount: 2,
          data: <<1, 2, 3>>,
          access_list: [<<2::160>>, <<3::160>>],
          signature_y_parity: true,
          signature_r: <<0x01::256>>,
          signature_s: <<0x02::256>>
        }
    """
    def add_signature(
          transaction = %__MODULE__{},
          v,
          r = <<_::256>>,
          s = <<_::256>>
        )
        when is_boolean(v) do
      %{transaction | signature_y_parity: v, signature_r: r, signature_s: s}
    end

    def add_signature(
          transaction = %__MODULE__{},
          <<r::binary-size(32), s::binary-size(32), v_bin::binary>>
        ) do
      v = :binary.decode_unsigned(v_bin)
      y_parity =
        if v < 2 do
          v == 1
        else
          rem(v, 2) == 0
        end

      %{transaction | signature_y_parity: y_parity, signature_r: r, signature_s: s}
    end

    @doc ~S"""
    Recovers a signature from a transaction, if it's been signed. Otherwise returns an error.

    ## Examples

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], true, <<0x01::256>>, <<0x02::256>>, :goerli)
        ...> |> Signet.Transaction.V2.get_signature()
        {:ok, <<1::256, 2::256, 1::8>>}

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
        ...> |> Signet.Transaction.V2.get_signature()
        {:error, "transaction missing signature"}
    """
    def get_signature(%__MODULE__{signature_y_parity: v, signature_r: r, signature_s: s})
        when is_nil(v) or is_nil(r) or is_nil(s),
        do: {:error, "transaction missing signature"}

    def get_signature(%__MODULE__{signature_y_parity: v, signature_r: r, signature_s: s}) do
      v_enc = :binary.encode_unsigned(if v, do: 1, else: 0)
      {:ok, <<r::binary-size(32), s::binary-size(32), v_enc::binary>>}
    end

    @doc ~S"""
    Recovers the signer from a given transaction, if it's been signed.

    ## Examples

        iex> {:ok, address} =
        ...>   Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], true, <<0x01::256>>, <<0x02::256>>, :goerli)
        ...>   |> Signet.Transaction.V2.recover_signer()
        ...> Signet.Hex.to_address(address)
        "0xC002Ca628F93e1550b5f30Ed10902A9e7783364B"

        iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
        ...> |> Signet.Transaction.V2.recover_signer()
        {:error, "transaction missing signature"}
    """
    def recover_signer(transaction) do
      trx_encoded =
        encode(%{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil})

      with {:ok, signature} <- get_signature(transaction) do
        {:ok, Signet.Recover.recover_eth(trx_encoded, signature)}
      end
    end
  end

  @doc """
  Builds a v1-style call to a given contract

  ## Examples

      iex> use Signet.Hex
      iex> Signet.Transaction.build_trx(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, 100_000, 0, 5)
      %Signet.Transaction.V1{
        nonce: 5,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<1::160>>,
        value: 0,
        data: ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001],
        v: 5,
        r: 0,
        s: 0
      }

      iex> use Signet.Hex
      iex> call_data = ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001]
      ...> Signet.Transaction.build_trx(<<1::160>>, 5, call_data, {50, :gwei}, 100_000, 0, 5)
      %Signet.Transaction.V1{
        nonce: 5,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<1::160>>,
        value: 0,
        data: ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001],
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

  @doc """
  Builds a v2 (eip-1559)-style call to a given contract

  ## Examples

      iex> use Signet.Hex
      iex> Signet.Transaction.build_trx_v2(<<1::160>>, 6, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, {10, :gwei}, 100_000, 0, [<<1::160>>], :goerli)
      %Signet.Transaction.V2{
        chain_id: 5,
        nonce: 6,
        max_priority_fee_per_gas: 50000000000,
        max_fee_per_gas: 10000000000,
        gas_limit: 100000,
        destination: <<1::160>>,
        amount: 0,
        data: ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001],
        access_list: [<<1::160>>],
        signature_y_parity: nil,
        signature_r: nil,
        signature_s: nil
      }

      iex> use Signet.Hex
      iex> call_data = ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001]
      ...> Signet.Transaction.build_trx_v2(<<1::160>>, 5, call_data, {50, :gwei}, {10, :gwei}, 100_000, 0, [<<1::160>>], :goerli)
      %Signet.Transaction.V2{
        chain_id: 5,
        nonce: 5,
        max_priority_fee_per_gas: 50000000000,
        max_fee_per_gas: 10000000000,
        gas_limit: 100000,
        destination: <<1::160>>,
        amount: 0,
        data: ~h[0xA291ADD600000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001],
        access_list: [<<1::160>>],
        signature_y_parity: nil,
        signature_r: nil,
        signature_s: nil
      }
  """
  def build_trx_v2(
        address,
        nonce,
        call_data,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        amount,
        access_list,
        chain_id \\ nil
      )
      when is_list(access_list) do
    data =
      case call_data do
        {abi, params} ->
          ABI.encode(abi, params)

        call_data when is_binary(call_data) ->
          call_data
      end

    V2.new(
      nonce,
      max_priority_fee_per_gas,
      max_fee_per_gas,
      gas_limit,
      address,
      amount,
      data,
      access_list,
      chain_id
    )
  end

  @doc ~S"""
  Builds and signs a transaction, to be ready to be passed to JSON-RPC.

  Optionally takes a callback to modify the transaction before it is signed.

  ## Examples

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, signed_trx} = Signet.Transaction.build_signed_trx(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, 100_000, 0, signer: signer_proc, chain_id: :goerli)
      iex> {:ok, signer} = Signet.Transaction.V1.recover_signer(signed_trx, 5)
      iex> Signet.Hex.to_address(signer)
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
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
         {:ok, signature} <- Signet.Signer.sign(transaction_encoded, signer, chain_id: chain_id) do
      {:ok, V1.add_signature(transaction, signature)}
    end
  end

  @doc ~S"""
  Builds and signs a V2 transaction, to be ready to be passed to JSON-RPC.

  Optionally takes a callback to modify the transaction before it is signed.

  ## Examples

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, signed_trx} = Signet.Transaction.build_signed_trx_v2(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, {10, :gwei}, 100_000, 0, [], signer: signer_proc, chain_id: :goerli)
      iex> {:ok, signer} = Signet.Transaction.V2.recover_signer(signed_trx)
      iex> Signet.Hex.to_address(signer)
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  def build_signed_trx_v2(
        address,
        nonce,
        call_data,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        amount,
        access_list,
        opts \\ []
      )
      when is_list(access_list) do
    signer = Keyword.get(opts, :signer, Signet.Signer.Default)
    chain_id = Keyword.get(opts, :chain_id, nil)
    callback = Keyword.get(opts, :callback, nil)

    transaction =
      build_trx_v2(
        address,
        nonce,
        call_data,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        amount,
        access_list,
        chain_id
      )

    callback = if(is_nil(callback), do: fn trx -> {:ok, trx} end, else: callback)

    with {:ok, transaction} <- callback.(transaction),
         transaction_encoded <- V2.encode(transaction),
         {:ok, signature} <- Signet.Signer.sign(transaction_encoded, signer, chain_id: chain_id) do
      {:ok, V2.add_signature(transaction, signature)}
    end
  end
end

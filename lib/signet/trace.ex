defmodule Signet.Trace do
  @moduledoc ~S"""
  Represents an Ethereum transaction trace, which contains information
  about the call graph of an executed transaction.

  See `Signet.RPC.trace_transaction` for getting traces from
  an Ethereum JSON-RPC host.

  See also:
    * Alcemy docs: https://docs.alchemy.com/reference/trace-transaction
    * Infura docs: https://docs.infura.io/networks/ethereum/json-rpc-methods/trace-methods/trace_transaction
    * Infura trace object: https://docs.infura.io/networks/ethereum/json-rpc-methods/trace-methods/#trace
  """

  defmodule Action do
    @type t() :: %__MODULE__{
            call_type: String.t(),
            from: <<_::160>>,
            gas: integer(),
            input: binary(),
            to: <<_::160>>,
            value: integer()
          }

    defstruct [
      :call_type,
      :from,
      :gas,
      :input,
      :to,
      :value
    ]

    @doc ~S"""
    Deserializes a trace sub-action into a struct.

    ## Examples

        iex> %{
        ...>   "callType" => "call",
        ...>   "from" => "0x83806d539d4ea1c140489a06660319c9a303f874",
        ...>   "gas" => "0x1a1f8",
        ...>   "input" => "0x",
        ...>   "to" => "0x1c39ba39e4735cb65978d4db400ddd70a72dc750",
        ...>   "value" => "0x7a16c911b4d00000"
        ...> }
        ...> |> Signet.Trace.Action.deserialize()
        %Signet.Trace.Action{
          call_type: "call",
          from: Signet.Util.decode_hex!("0x83806d539d4ea1c140489a06660319c9a303f874"),
          gas: 0x01a1f8,
          input: <<>>,
          to: Signet.Util.decode_hex!("0x1c39ba39e4735cb65978d4db400ddd70a72dc750"),
          value: 0x7a16c911b4d00000,
        }
    """
    @spec deserialize(map()) :: t() | no_return()
    def deserialize(params = %{"callType" => call_type}) when is_binary(call_type) do
      %__MODULE__{
        call_type: call_type,
        from: Signet.Util.decode_address!(params["from"]),
        gas: Signet.Util.decode_hex_number!(params["gas"]),
        input: Signet.Util.decode_hex!(params["input"]),
        to: Signet.Util.decode_address!(params["to"]),
        value: Signet.Util.decode_hex_number!(params["value"])
      }
    end
  end

  @type t() :: %__MODULE__{
          action: Action.t(),
          block_hash: <<_::256>>,
          block_number: integer(),
          gas_used: integer(),
          output: binary(),
          subtraces: integer(),
          trace_address: <<_::160>>,
          transaction_hash: <<_::256>>,
          transaction_position: integer(),
          type: String.t()
        }

  defstruct [
    :action,
    :block_hash,
    :block_number,
    :gas_used,
    :output,
    :subtraces,
    :trace_address,
    :transaction_hash,
    :transaction_position,
    :type
  ]

  @doc ~S"""
  Deserializes a single trace result from `trace_transction`. Note: a JSON-RPC response will
  return an array of such traces.

  ## Examples

      iex> %{
      ...>   "action" => %{
      ...>     "callType" => "call",
      ...>     "from" => "0x83806d539d4ea1c140489a06660319c9a303f874",
      ...>     "gas" => "0x1a1f8",
      ...>     "input" => "0x",
      ...>     "to" => "0x1c39ba39e4735cb65978d4db400ddd70a72dc750",
      ...>     "value" => "0x7a16c911b4d00000"
      ...>   },
      ...>   "blockHash" => "0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add",
      ...>   "blockNumber" => 3068185,
      ...>   "result" => %{
      ...>     "gasUsed" => "0x2982",
      ...>     "output" => "0x"
      ...>   },
      ...>   "subtraces" => 2,
      ...>   "traceAddress" => ["0x1c39ba39e4735cb65978d4db400ddd70a72dc750"],
      ...>   "transactionHash" => "0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3",
      ...>   "transactionPosition" => 2,
      ...>   "type" => "call"
      ...> }
      ...> |> Signet.Trace.deserialize()
      %Signet.Trace{
        action: %Signet.Trace.Action{
          call_type: "call",
          from: Signet.Util.decode_hex!("0x83806d539d4ea1c140489a06660319c9a303f874"),
          gas: 0x01a1f8,
          input: <<>>,
          to: Signet.Util.decode_hex!("0x1c39ba39e4735cb65978d4db400ddd70a72dc750"),
          value: 0x7a16c911b4d00000,
        },
        block_hash: Signet.Util.decode_hex!("0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add"),
        block_number: 3068185,
        gas_used: 0x2982,
        output: <<>>,
        subtraces: 2,
        trace_address: [Signet.Util.decode_hex!("0x1c39ba39e4735cb65978d4db400ddd70a72dc750")],
        transaction_hash: Signet.Util.decode_hex!("0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3"),
        transaction_position: 2,
        type: "call"
      }
  """
  @spec deserialize(map()) :: t() | no_return()
  def deserialize(
        params = %{
          "blockNumber" => block_number,
          "subtraces" => subtraces,
          "transactionPosition" => transaction_position,
          "type" => type
        }
      )
      when is_integer(block_number) and is_integer(subtraces) and is_integer(transaction_position) and
             is_binary(type) do
    %__MODULE__{
      action: Action.deserialize(params["action"]),
      block_hash: Signet.Util.decode_word!(params["blockHash"]),
      block_number: block_number,
      gas_used: Signet.Util.decode_hex_number!(params["result"]["gasUsed"]),
      output: Signet.Util.decode_hex!(params["result"]["output"]),
      subtraces: subtraces,
      trace_address: Enum.map(params["traceAddress"], &Signet.Util.decode_address!/1),
      transaction_hash: Signet.Util.decode_word!(params["transactionHash"]),
      transaction_position: transaction_position,
      type: type
    }
  end

  @doc ~S"""
  Deserializes an array of trace results from `trace_transction`.

  ## Examples

      iex> [%{
      ...>   "action" => %{
      ...>     "callType" => "call",
      ...>     "from" => "0x83806d539d4ea1c140489a06660319c9a303f874",
      ...>     "gas" => "0x1a1f8",
      ...>     "input" => "0x",
      ...>     "to" => "0x1c39ba39e4735cb65978d4db400ddd70a72dc750",
      ...>     "value" => "0x7a16c911b4d00000"
      ...>   },
      ...>   "blockHash" => "0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add",
      ...>   "blockNumber" => 3068185,
      ...>   "result" => %{
      ...>     "gasUsed" => "0x2982",
      ...>     "output" => "0x"
      ...>   },
      ...>   "subtraces" => 2,
      ...>   "traceAddress" => ["0x1c39ba39e4735cb65978d4db400ddd70a72dc750"],
      ...>   "transactionHash" => "0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3",
      ...>   "transactionPosition" => 2,
      ...>   "type" => "call"
      ...> }]
      ...> |> Signet.Trace.deserialize_many()
      [
        %Signet.Trace{
          action: %Signet.Trace.Action{
            call_type: "call",
            from: Signet.Util.decode_hex!("0x83806d539d4ea1c140489a06660319c9a303f874"),
            gas: 0x01a1f8,
            input: <<>>,
            to: Signet.Util.decode_hex!("0x1c39ba39e4735cb65978d4db400ddd70a72dc750"),
            value: 0x7a16c911b4d00000,
          },
          block_hash: Signet.Util.decode_hex!("0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add"),
          block_number: 3068185,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [Signet.Util.decode_hex!("0x1c39ba39e4735cb65978d4db400ddd70a72dc750")],
          transaction_hash: Signet.Util.decode_hex!("0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3"),
          transaction_position: 2,
          type: "call"
        }
      ]
  """
  @spec deserialize_many([map()]) :: [t()] | no_return()
  def deserialize_many(traces), do: Enum.map(traces, &Signet.Trace.deserialize/1)
end

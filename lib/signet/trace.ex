defmodule Signet.Trace do
  @moduledoc ~S"""
  Represents an Ethereum transaction trace, which contains information
  about the call graph of an executed transaction.

  See `Signet.RPC.trace_transaction` for getting traces from
  an Ethereum JSON-RPC host.

  See also:
    * Alchemy docs: https://docs.alchemy.com/reference/trace-transaction
    * Infura docs: https://docs.infura.io/networks/ethereum/json-rpc-methods/trace-methods/trace_transaction
    * Infura trace object: https://docs.infura.io/networks/ethereum/json-rpc-methods/trace-methods/#trace
  """

  defmodule Action do
    @type t() :: %__MODULE__{
            call_type: String.t() | nil,
            init: binary() | nil,
            from: <<_::160>>,
            gas: integer(),
            input: binary(),
            to: <<_::160>> | nil,
            value: integer()
          }

    defstruct [
      :call_type,
      :init,
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

        iex> %{
        ...>   "callType" => "call",
        ...>   "from" => "0x0000000000000000000000000000000000000000",
        ...>   "gas" => "0x1dcd0f58",
        ...>   "input" =>
        ...>     "0xd1692f56000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a6120000000000000000000000000000000000000000000000000000000000000000",
        ...>   "to" => "0x13172ee393713fba9925a9a752341ebd31e8d9a7",
        ...>   "value" => "0x0"
        ...> }
        ...> |> Signet.Trace.Action.deserialize()
        %Signet.Trace.Action{
          call_type: "call",
          from: Signet.Util.decode_hex!("0x0000000000000000000000000000000000000000"),
          gas: 0x1dcd0f58,
          input: Signet.Util.decode_hex!("0xd1692f56000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a6120000000000000000000000000000000000000000000000000000000000000000"),
          to: Signet.Util.decode_hex!("0x13172ee393713fba9925a9a752341ebd31e8d9a7"),
          value: 0x0,
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

    def deserialize(params = %{"init" => init}) when is_binary(init) do
      %__MODULE__{
        init: Signet.Util.decode_hex!(init),
        from: Signet.Util.decode_address!(params["from"]),
        gas: Signet.Util.decode_hex_number!(params["gas"]),
        value: Signet.Util.decode_hex_number!(params["value"])
      }
    end
  end

  @type t() :: %__MODULE__{
          action: Action.t(),
          block_hash: <<_::256>>,
          block_number: integer(),
          gas_used: integer(),
          error: String.t() | nil,
          output: binary() | nil,
          result_code: binary() | nil,
          result_address: <<_::160>> | nil,
          subtraces: integer(),
          trace_address: <<_::160>> | integer(),
          transaction_hash: <<_::256>>,
          transaction_position: integer(),
          type: String.t()
        }

  defstruct [
    :action,
    :block_hash,
    :block_number,
    :gas_used,
    :error,
    :output,
    :result_code,
    :result_address,
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

      iex> %{
      ...>   "action" => %{
      ...>     "from" => "0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97",
      ...>     "gas" => "0x4ad07",
      ...>     "init" =>
      ...>       "0x60e03461009157601f6101ec38819003918201601f19168301916001600160401b038311848410176100965780849260609460405283398101031261009157610047816100ac565b906100606040610059602084016100ac565b92016100ac565b9060805260a05260c05260405161012b90816100c18239608051816088015260a051816045015260c0518160c60152f35b600080fd5b634e487b7160e01b600052604160045260246000fd5b51906001600160a01b03821682036100915756fe608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03166080908152602090f35b600036818037808036817f00000000000000000000000000000000000000000000000000000000000000005af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c634300081700330000000000000000000000009eecb6f3c9b7516094ed78e2e0e76201cbd6aac00000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e",
      ...>     "value" => "0x0"
      ...>   },
      ...>   "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
      ...>   "blockNumber" => 10_493_512,
      ...>   "result" => %{
      ...>     "address" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
      ...>     "code" =>
      ...>       "0x608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e6001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e6001600160a01b03166080908152602090f35b600036818037808036817f0000000000000000000000009eecb6f3c9b7516094ed78e2e0e76201cbd6aac05af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c63430008170033",
      ...>     "gasUsed" => "0xebe8"
      ...>   },
      ...>   "subtraces" => 0,
      ...>   "traceAddress" => [0],
      ...>   "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
      ...>   "transactionPosition" => 0,
      ...>   "type" => "create"
      ...> }
      ...> |> Signet.Trace.deserialize()
      %Signet.Trace{
        action: %Signet.Trace.Action{
          call_type: nil,
          init: Signet.Util.decode_hex!("0x60e03461009157601f6101ec38819003918201601f19168301916001600160401b038311848410176100965780849260609460405283398101031261009157610047816100ac565b906100606040610059602084016100ac565b92016100ac565b9060805260a05260c05260405161012b90816100c18239608051816088015260a051816045015260c0518160c60152f35b600080fd5b634e487b7160e01b600052604160045260246000fd5b51906001600160a01b03821682036100915756fe608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03166080908152602090f35b600036818037808036817f00000000000000000000000000000000000000000000000000000000000000005af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c634300081700330000000000000000000000009eecb6f3c9b7516094ed78e2e0e76201cbd6aac00000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e"),
          from: Signet.Util.decode_hex!("0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97"),
          gas: 306439,
          input: nil,
          to: nil,
          value: 0
        },
        block_hash: Signet.Util.decode_hex!("0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2"),
        block_number: 10493512,
        gas_used: 60392,
        output: nil,
        result_address: Signet.Util.decode_hex!("0x107eed62216e0f83218858cef6830d1b17ad6bc3"),
        result_code: Signet.Util.decode_hex!("0x608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e6001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f0000000000000000000000005af819e8d1bf8c87e3107441fb799e4f1876448e6001600160a01b03166080908152602090f35b600036818037808036817f0000000000000000000000009eecb6f3c9b7516094ed78e2e0e76201cbd6aac05af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c63430008170033"),
        subtraces: 0,
        trace_address: [0],
        transaction_hash: Signet.Util.decode_hex!("0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303"),
        transaction_position: 0,
        type: "create"
      }

      iex> %{
      ...>   "action" => %{
      ...>     "callType" => "call",
      ...>     "from" => "0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97",
      ...>     "gas" => "0x3b933",
      ...>     "input" =>
      ...>       "0x7fba1a4e0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001c46fc4208ee27643f7686feef2c622aa192a12a12e023eb3a0a5acdef9c3663e52554479549cdf9d47b467ddf33dd8807535f0d5875968b318ce01e8ca40281490000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000007104f0080000000000000000000000000000000000000000000000000000000000000019630102030460005232620000135760006000f35b6004601cfd00000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002",
      ...>     "to" => "0x107eed62216e0f83218858cef6830d1b17ad6bc3",
      ...>     "value" => "0x0"
      ...>   },
      ...>   "blockHash" => "0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2",
      ...>   "blockNumber" => 10_493_512,
      ...>   "error" => "Reverted",
      ...>   "result" => %{"gasUsed" => "0x1bfa6", "output" => "0x01020304"},
      ...>   "subtraces" => 1,
      ...>   "traceAddress" => [1],
      ...>   "transactionHash" => "0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303",
      ...>   "transactionPosition" => 0,
      ...>   "type" => "call"
      ...> }
      ...> |> Signet.Trace.deserialize()
      %Signet.Trace{
        action: %Signet.Trace.Action{
          call_type: "call",
          from: Signet.Util.decode_hex!("0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97"),
          gas: 0x3b933,
          input: Signet.Util.decode_hex!("0x7fba1a4e0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001c46fc4208ee27643f7686feef2c622aa192a12a12e023eb3a0a5acdef9c3663e52554479549cdf9d47b467ddf33dd8807535f0d5875968b318ce01e8ca40281490000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000007104f0080000000000000000000000000000000000000000000000000000000000000019630102030460005232620000135760006000f35b6004601cfd00000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002"),
          to: Signet.Util.decode_hex!("0x107eed62216e0f83218858cef6830d1b17ad6bc3"),
          value: 0x0,
        },
        block_hash: Signet.Util.decode_hex!("0x151ccedeab15a443b3c45719ff00404d9b1d431454e6f63c845b22c46c9d25e2"),
        block_number: 10_493_512,
        gas_used: 0x1bfa6,
        error: "Reverted",
        output: Signet.Util.decode_hex!("0x01020304"),
        subtraces: 1,
        trace_address: [1],
        transaction_hash: Signet.Util.decode_hex!("0xd2cb84e759a8882f8c3de29b673f6a602e0cae7f37a440b957526ef76eb05303"),
        transaction_position: 0,
        type: "call"
      }

      iex> %{
      ...>   "action" => %{
      ...>     "callType" => "call",
      ...>     "from" => "0x0000000000000000000000000000000000000000",
      ...>     "gas" => "0x1dcd0f58",
      ...>     "input" =>
      ...>       "0xd1692f56000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a6120000000000000000000000000000000000000000000000000000000000000000",
      ...>     "to" => "0x13172ee393713fba9925a9a752341ebd31e8d9a7",
      ...>     "value" => "0x0"
      ...>   },
      ...>   "error" => "Reverted",
      ...>   "result" => %{"gasUsed" => "0x1d55dd47", "output" => "0x"},
      ...>   "subtraces" => 1,
      ...>   "traceAddress" => [],
      ...>   "type" => "call"
      ...> }
      ...> |> Signet.Trace.deserialize()
      %Signet.Trace{
        action: %Signet.Trace.Action{
          call_type: "call",
          from: Signet.Util.decode_hex!("0x0000000000000000000000000000000000000000"),
          gas: 0x1dcd0f58,
          input: Signet.Util.decode_hex!("0xd1692f56000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a6120000000000000000000000000000000000000000000000000000000000000000"),
          to: Signet.Util.decode_hex!("0x13172ee393713fba9925a9a752341ebd31e8d9a7"),
          value: 0x0,
        },
        block_hash: nil,
        block_number: nil,
        gas_used: 0x1d55dd47,
        error: "Reverted",
        output: <<>>,
        subtraces: 1,
        trace_address: [],
        transaction_hash: nil,
        type: "call"
      }

      iex> %{
      ...>   "action" => %{
      ...>     "from" => "0x13172ee393713fba9925a9a752341ebd31e8d9a7",
      ...>     "gas" => "0x1d555c99",
      ...>     "init" =>
      ...>       "0x60e03461009157601f6101ec38819003918201601f19168301916001600160401b038311848410176100965780849260609460405283398101031261009157610047816100ac565b906100606040610059602084016100ac565b92016100ac565b9060805260a05260c05260405161012b90816100c18239608051816088015260a051816045015260c0518160c60152f35b600080fd5b634e487b7160e01b600052604160045260246000fd5b51906001600160a01b03821682036100915756fe608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03166080908152602090f35b600036818037808036817f00000000000000000000000000000000000000000000000000000000000000005af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c6343000817003300000000000000000000000049e5d261e95f6a02505078bb339fecb210a0b634000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612",
      ...>     "value" => "0x0"
      ...>   },
      ...>   "error" => "contract address collision",
      ...>   "result" => nil,
      ...>   "subtraces" => 0,
      ...>   "traceAddress" => [0],
      ...>   "type" => "create"
      ...> }
      ...> |> Signet.Trace.deserialize()
      %Signet.Trace{
        action: %Signet.Trace.Action{
          from: Signet.Util.decode_hex!("0x13172ee393713fba9925a9a752341ebd31e8d9a7"),
          gas: 0x1d555c99,
          init: Signet.Util.decode_hex!("0x60e03461009157601f6101ec38819003918201601f19168301916001600160401b038311848410176100965780849260609460405283398101031261009157610047816100ac565b906100606040610059602084016100ac565b92016100ac565b9060805260a05260c05260405161012b90816100c18239608051816088015260a051816045015260c0518160c60152f35b600080fd5b634e487b7160e01b600052604160045260246000fd5b51906001600160a01b03821682036100915756fe608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03166080908152602090f35b600036818037808036817f00000000000000000000000000000000000000000000000000000000000000005af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c6343000817003300000000000000000000000049e5d261e95f6a02505078bb339fecb210a0b634000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612"),
          value: 0x0,
        },
        error: "contract address collision",
        subtraces: 0,
        trace_address: [0],
        type: "create"
      }
  """
  @spec deserialize(map()) :: t() | no_return()
  def deserialize(
        params = %{
          "subtraces" => subtraces,
          "type" => type
        }
      )
      when is_integer(subtraces) and is_binary(type) do
    %__MODULE__{
      action: Action.deserialize(params["action"]),
      block_hash: map(get_in(params, ["blockHash"]), &Signet.Util.decode_word!/1),
      block_number: params["blockNumber"],
      gas_used: map(get_in(params, ["result", "gasUsed"]), &Signet.Util.decode_hex_number!/1),
      error: if(Map.has_key?(params, "error"), do: params["error"], else: nil),
      output: map(get_in(params, ["result", "output"]), &Signet.Util.decode_hex!/1),
      subtraces: subtraces,
      trace_address: Enum.map(params["traceAddress"], &decode_address_or_number/1),
      transaction_hash: map(get_in(params, ["transactionHash"]), &Signet.Util.decode_word!/1),
      transaction_position: params["transactionPosition"],
      result_code: map(get_in(params, ["result", "code"]), &Signet.Util.decode_hex!/1),
      result_address: map(get_in(params, ["result", "address"]), &Signet.Util.decode_address!/1),
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

  defp decode_address_or_number(b) when is_binary(b), do: Signet.Util.decode_address!(b)
  defp decode_address_or_number(n) when is_integer(n), do: n

  defp map(x, f) do
    if is_nil(x), do: nil, else: f.(x)
  end
end

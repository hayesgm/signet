defmodule Signet.FeeHistory do
  @moduledoc ~S"""
  Represents fee history data as defined in EIP-1559.

  See `Signet.RPC.fee_history` for getting traces from
  an Ethereum JSON-RPC host.

  See also:
    * Alcemy docs: https://docs.alchemy.com/reference/eth-feehistory
    * Infura docs: https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_feehistory
  """

  @type t() :: %__MODULE__{
          oldest_block: integer(),
          base_fee_per_gas: [integer()],
          gas_used_ratio: [integer()],
          reward: [[float()]]
        }

  defstruct [
    :oldest_block,
    :base_fee_per_gas,
    :gas_used_ratio,
    :reward
  ]

  @doc ~S"""
  Deserializes fee history data from `eth_feeHistory` RPC response.

  ## Examples

      iex> %{
      ...>   "oldestBlock" => "0xfd6a75",
      ...>   "reward" => [
      ...>     [
      ...>       "0x3b9aca00",
      ...>       "0x3b9aca00",
      ...>       "0x59682f00"
      ...>     ],
      ...>     [
      ...>       "0x3b9aca00",
      ...>       "0x3b9aca00",
      ...>       "0x77359400"
      ...>     ],
      ...>     [
      ...>       "0x3b9aca00",
      ...>       "0x3b9aca00",
      ...>       "0x3b9aca00"
      ...>     ],
      ...>     [
      ...>       "0x2e7ddb00",
      ...>       "0x3b9aca00",
      ...>       "0x77359400"
      ...>     ],
      ...>     [
      ...>       "0x3b9aca00",
      ...>       "0x3b9aca00",
      ...>       "0x59682f00"
      ...>     ]
      ...>   ],
      ...>   "baseFeePerGas" => [
      ...>     "0x4c9d974c3",
      ...>     "0x4c38a847a",
      ...>     "0x49206d475",
      ...>     "0x47ac58b63",
      ...>     "0x471e805d8",
      ...>     "0x46f5f64a6"
      ...>   ],
      ...>   "gasUsedRatio" => [
      ...>     0.4794155666666667,
      ...>     0.3375966,
      ...>     0.42049746666666665,
      ...>     0.4690773,
      ...>     0.49109343333333333
      ...>   ]
      ...> }
      ...> |> Signet.FeeHistory.deserialize()
      %Signet.FeeHistory{
        base_fee_per_gas: [20566340803, 20460504186, 19629790325, 19239635811, 19090900440, 19048391846],
        gas_used_ratio: [0.4794155666666667, 0.3375966, 0.42049746666666665, 0.4690773, 0.49109343333333333],
        oldest_block: 16607861,
        reward: [[1000000000, 1000000000, 1500000000], [1000000000, 1000000000, 2000000000], [1000000000, 1000000000, 1000000000], [780000000, 1000000000, 2000000000], [1000000000, 1000000000, 1500000000]]
      }
  """
  @spec deserialize(map()) :: t() | no_return()
  def deserialize(%{
        "oldestBlock" => oldest_block,
        "reward" => reward,
        "baseFeePerGas" => base_fee_per_gas,
        "gasUsedRatio" => gas_used_ratio
      }) do
    %__MODULE__{
      oldest_block: Signet.Util.decode_hex_number!(oldest_block),
      base_fee_per_gas: Enum.map(base_fee_per_gas, &Signet.Util.decode_hex_number!/1),
      gas_used_ratio: gas_used_ratio,
      reward: Enum.map(reward, fn r -> Enum.map(r, &Signet.Util.decode_hex_number!/1) end)
    }
  end
end

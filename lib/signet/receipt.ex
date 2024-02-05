defmodule Signet.Receipt do
  @moduledoc ~S"""
  Represents an Ethereum transaction receipt, which contains information
  about the success or failure of an Ethereum transaction after it has
  been included in a mined Ethereum block.

  See `Signet.RPC.get_transaction_receipt` for getting receipts from
  an Ethereum JSON-RPC host.
  """

  defmodule Log do
    @type t() :: %__MODULE__{
      log_index: integer(), # QUANTITY - integer of the log index position in the block. null when its pending log.
      block_number: integer(), # QUANTITY - the block number where this log was in. null when its pending. null when its pending log.
      block_hash: <<_::256>>, # DATA, 32 Bytes - hash of the block where this log was in. null when its pending. null when its pending log.
      transaction_hash: <<_::256>>, # DATA, 32 Bytes - hash of the transactions this log was created from. null when its pending log.
      transaction_index: integer(), # QUANTITY - integer of the transactions index position log was created from. null when its pending log.
      address: <<_::160>>, # DATA, 20 Bytes - address from which this log originated. 
      data: binary, # DATA - contains zero or more 32 Bytes non-indexed arguments of the log.
      topics: [<<_::256>>] # rray of DATA - Array of 0 to 4 32 Bytes DATA of indexed log arguments. (In solidity: The first topic is the hash of the signature of the event (e.g. Deposit(address,bytes32,uint256)), except you declared the event with the anonymous specifier.)
    }

    defstruct [
      :log_index,
      :block_number,
      :block_hash,
      :transaction_hash,
      :transaction_index,
      :address,
      :data,
      :topics,
    ]

    @doc ~S"""
    Deserializes a transaction receipt as serialized by an Ethereum JSON-RPC response.

    See also https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt

    ## Examples

        iex> %{
        ...>   "logIndex" => "0x1",
        ...>   "blockNumber" => "0x1b4",
        ...>   "blockHash" => "0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3",
        ...>   "transactionHash" =>  "0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf",
        ...>   "transactionIndex" => "0x0",
        ...>   "address" => "0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d",
        ...>   "data" => "0x0000000000000000000000000000000000000000000000000000000000000000",
        ...>   "topics" => [
        ...>     "0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5"
        ...>   ]
        ...> }
        ...> |> Signet.Receipt.Log.deserialize()
        %Signet.Receipt.Log{
          log_index: 1,
          block_number: 0x01b4,
          block_hash: Signet.Util.decode_hex!("0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3"),
          transaction_hash: Signet.Util.decode_hex!("0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf"),
          transaction_index: 0,
          address: Signet.Util.decode_hex!("0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d"),
          data: Signet.Util.decode_hex!("0x0000000000000000000000000000000000000000000000000000000000000000"),
          topics: [
            Signet.Util.decode_hex!("0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5")
          ]
        }
    """
    @spec deserialize(map()) :: t() | no_return()
    def deserialize(params=%{}) do
      %__MODULE__{
        log_index: Signet.Util.decode_hex_number!(params["logIndex"]),
        block_number: Signet.Util.decode_hex_number!(params["blockNumber"]),
        block_hash: Signet.Util.decode_word!(params["blockHash"]),
        transaction_hash: Signet.Util.decode_word!(params["transactionHash"]),
        transaction_index: Signet.Util.decode_hex_number!(params["transactionIndex"]),
        address: Signet.Util.decode_address!(params["address"]),
        data: Signet.Util.decode_hex!(params["data"]),
        topics: Enum.map(params["topics"], &Signet.Util.decode_word!/1)
      }
    end
  end

  @type t() :: %__MODULE__{
    transaction_hash: <<_::256>>, # DATA, 32 Bytes - hash of the transaction.
    transaction_index: integer(), # QUANTITY - integer of the transactions index position in the block.
    block_hash: <<_::256>>, # DATA, 32 Bytes - hash of the block where this transaction was in.
    block_number: integer(), # QUANTITY - block number where this transaction was in.
    from: <<_::160>>, # DATA, 20 Bytes - address of the sender.
    to: <<_::160>>, # DATA, 20 Bytes - address of the receiver. null when its a contract creation transaction.
    cumulative_gas_used: integer(), # QUANTITY - The total amount of gas used when this transaction was executed in the block.
    effective_gas_price: integer(), # QUANTITY - The sum of the base fee and tip paid per unit of gas.
    gas_used: integer(), # QUANTITY - The amount of gas used by this specific transaction alone.
    contract_address: <<_::160>> | nil, # DATA, 20 Bytes - The contract address created, if the transaction was a contract creation, otherwise null.
    logs: [Log.t()], # Array of log objects, which this transaction generated.
    logs_bloom: <<_::256>>, # DATA, 256 Bytes - Bloom filter for light clients to quickly retrieve related logs.
    type: integer(), # QUANTITY - integer of the transaction type, 0x0 for legacy transactions, 0x1 for access list types, 0x2 for dynamic fees.
    status: integer(), # QUANTITY either 1 (success) or 0 (failure)
  }

  defstruct [
    :transaction_hash,
    :transaction_index,
    :block_hash,
    :block_number,
    :from,
    :to,
    :cumulative_gas_used,
    :effective_gas_price,
    :gas_used,
    :contract_address,
    :logs,
    :logs_bloom,
    :type,
    :status,
  ]

  @doc ~S"""
  Deserializes a transaction receipt as serialized by an Ethereum JSON-RPC response.

  See also https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt

  ## Examples

      iex> %{
      ...>   "blockHash" => "0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3",
      ...>   "blockNumber" => "0xeff35f",
      ...>   "contractAddress" => nil,
      ...>   "cumulativeGasUsed" => "0xa12515",
      ...>   "effectiveGasPrice" => "0x5a9c688d4",
      ...>   "from" => "0x6221a9c005f6e47eb398fd867784cacfdcfff4e7",
      ...>   "gasUsed" => "0xb4c8",
      ...>   "logs" => [%{
      ...>     "logIndex" => "0x1",
      ...>     "blockNumber" => "0x1b4",
      ...>     "blockHash" => "0xaa8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcfdf829c5a142f1fccd7d",
      ...>     "transactionHash" =>  "0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf",
      ...>     "transactionIndex" => "0x0",
      ...>     "address" => "0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d",
      ...>     "data" => "0x0000000000000000000000000000000000000000000000000000000000000000",
      ...>     "topics" => [
      ...>       "0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5"
      ...>     ]
      ...>   }],
      ...>   "logsBloom" => "0x0000000000000000000000000000000000000000000000000000000000000001",
      ...>   "status" => "0x1",
      ...>   "to" => "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
      ...>   "transactionHash" =>
      ...>     "0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5",
      ...>   "transactionIndex" => "0x66",
      ...>   "type" => "0x2"
      ...> }
      ...> |> Signet.Receipt.deserialize()
      %Signet.Receipt{
        transaction_hash: Signet.Util.decode_hex!("0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5"),
        transaction_index: 0x66,
        block_hash: Signet.Util.decode_hex!("0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3"),
        block_number: 0xeff35f,
        from: Signet.Util.decode_hex!("0x6221a9c005f6e47eb398fd867784cacfdcfff4e7"),
        to: Signet.Util.decode_hex!("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"),
        cumulative_gas_used: 0xa12515,
        effective_gas_price: 0x5a9c688d4,
        gas_used: 0xb4c8,
        contract_address: nil,
        logs: [
          %Signet.Receipt.Log{
            log_index: 1,
            block_number: 0x01b4,
            block_hash: Signet.Util.decode_hex!("0xaa8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcfdf829c5a142f1fccd7d"),
            transaction_hash: Signet.Util.decode_hex!("0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf"),
            transaction_index: 0,
            address: Signet.Util.decode_hex!("0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d"),
            data: Signet.Util.decode_hex!("0x0000000000000000000000000000000000000000000000000000000000000000"),
            topics: [
              Signet.Util.decode_hex!("0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5")
            ]
          }
        ],
        logs_bloom: Signet.Util.decode_hex!("0x0000000000000000000000000000000000000000000000000000000000000001"),
        type: 0x02,
        status: 0x01,
      }
  """
  @spec deserialize(map()) :: t() | no_return()
  def deserialize(params=%{}) do
    %__MODULE__{
      transaction_hash: Signet.Util.decode_word!(params["transactionHash"]),
      transaction_index: Signet.Util.decode_hex_number!(params["transactionIndex"]),
      block_hash: Signet.Util.decode_word!(params["blockHash"]),
      block_number: Signet.Util.decode_hex_number!(params["blockNumber"]),
      from: Signet.Util.decode_address!(params["from"]),
      to: Signet.Util.decode_address!(params["to"]),
      cumulative_gas_used: Signet.Util.decode_hex_number!(params["cumulativeGasUsed"]),
      effective_gas_price: Signet.Util.decode_hex_number!(params["effectiveGasPrice"]),
      gas_used: Signet.Util.decode_hex_number!(params["gasUsed"]),
      contract_address: (if is_nil(params["contractAddress"]), do: nil, else: Signet.Util.decode_address!(params["contractAddress"])),
      logs: Enum.map(params["logs"], &Log.deserialize/1),
      logs_bloom: Signet.Util.decode_word!(params["logsBloom"]),
      type: Signet.Util.decode_hex_number!(params["type"]),
      status: Signet.Util.decode_hex_number!(params["status"])
    }
  end
end
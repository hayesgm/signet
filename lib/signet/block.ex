defmodule Signet.Block do
  @moduledoc ~S"""
  Represents a block from the Ethereum JSON-RPC endpoint.

  Defined here: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getblockbyhash
  """

  use Signet.Hex

  defstruct [
    :number,
    :hash,
    :parent_hash,
    :nonce,
    :sha3_uncles,
    :logs_bloom,
    :transactions_root,
    :state_root,
    :receipts_root,
    :miner,
    :difficulty,
    :total_difficulty,
    :extra_data,
    :size,
    :gas_limit,
    :gas_used,
    :timestamp,
    :transactions,
    :uncles
  ]

  @type t :: %__MODULE__{
          # number: QUANTITY - the block number. null when its pending block.
          number: integer() | nil,
          # hash: DATA, 32 Bytes - hash of the block. null when its pending block.
          hash: <<_::256>> | nil,
          # parentHash: DATA, 32 Bytes - hash of the parent block.
          parent_hash: <<_::256>> | nil,
          # nonce: DATA, 8 Bytes - hash of the generated proof-of-work. null when its pending block.
          nonce: integer() | nil,
          # sha3Uncles: DATA, 32 Bytes - SHA3 of the uncles data in the block.
          sha3_uncles: <<_::256>>,
          # logsBloom: DATA, 256 Bytes - the bloom filter for the logs of the block. null when its pending block.
          logs_bloom: <<_::1024>> | nil,
          # transactionsRoot: DATA, 32 Bytes - the root of the transaction trie of the block.
          transactions_root: <<_::256>>,
          # stateRoot: DATA, 32 Bytes - the root of the final state trie of the block.
          state_root: <<_::256>>,
          # receiptsRoot: DATA, 32 Bytes - the root of the receipts trie of the block.
          receipts_root: <<_::256>>,
          # miner: DATA, 20 Bytes - the address of the beneficiary to whom the mining rewards were given.
          miner: <<_::160>>,
          # difficulty: QUANTITY - integer of the difficulty for this block.
          difficulty: integer(),
          # totalDifficulty: QUANTITY - integer of the total difficulty of the chain until this block.
          total_difficulty: integer(),
          # extraData: DATA - the "extra data" field of this block.
          extra_data: binary(),
          # size: QUANTITY - integer the size of this block in bytes.
          size: integer(),
          # gasLimit: QUANTITY - the maximum gas allowed in this block.
          gas_limit: integer(),
          # gasUsed: QUANTITY - the total used gas by all transactions in this block.
          gas_used: integer(),
          # timestamp: QUANTITY - the unix timestamp for when the block was collated.
          timestamp: integer(),
          # transactions: Array - Array of transaction objects, or 32 Bytes transaction hashes depending on the last given parameter.
          transactions: [],
          # uncles: Array - Array of uncle hashes.
          uncles: [<<_::256>>]
        }

  @doc ~S"""
  Deserializes a block object from JSON-RPC.

  ## Examples

      iex> %{
      ...>   "difficulty" => "0x4ea3f27bc",
      ...>   "extraData" => "0x476574682f4c5649562f76312e302e302f6c696e75782f676f312e342e32",
      ...>   "gasLimit" => "0x1388",
      ...>   "gasUsed" => "0x0",
      ...>   "hash" => "0xdc0818cf78f21a8e70579cb46a43643f78291264dda342ae31049421c82d21ae",
      ...>   "logsBloom" => "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
      ...>   "miner" => "0xbb7b8287f3f0a933474a79eae42cbca977791171",
      ...>   "mixHash" => "0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843",
      ...>   "nonce" => "0x689056015818adbe",
      ...>   "number" => "0x1b4",
      ...>   "parentHash" => "0xe99e022112df268087ea7eafaf4790497fd21dbeeb6bd7a1721df161a6657a54",
      ...>   "receiptsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
      ...>   "sha3Uncles" => "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
      ...>   "size" => "0x220",
      ...>   "stateRoot" => "0xddc8b0234c2e0cad087c8b389aa7ef01f7d79b2570bccb77ce48648aa61c904d",
      ...>   "timestamp" => "0x55ba467c",
      ...>   "totalDifficulty" => "0x78ed983323d",
      ...>   "transactions" => [],
      ...>   "transactionsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
      ...>   "uncles" => []
      ...> }
      ...> |> Signet.Block.deserialize()
      %Signet.Block{
        difficulty: 0x4ea3f27bc,
        extra_data: ~h[0x476574682f4c5649562f76312e302e302f6c696e75782f676f312e342e32],
        gas_limit: 0x1388,
        gas_used: 0x0,
        hash: ~h[0xdc0818cf78f21a8e70579cb46a43643f78291264dda342ae31049421c82d21ae],
        logs_bloom: ~h[0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000],
        miner: ~h[0xbb7b8287f3f0a933474a79eae42cbca977791171],
        nonce: 0x689056015818adbe,
        number: 0x1b4,
        parent_hash: ~h[0xe99e022112df268087ea7eafaf4790497fd21dbeeb6bd7a1721df161a6657a54],
        receipts_root: ~h[0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421],
        sha3_uncles: ~h[0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347],
        size: 0x220,
        state_root: ~h[0xddc8b0234c2e0cad087c8b389aa7ef01f7d79b2570bccb77ce48648aa61c904d],
        timestamp: 0x55ba467c,
        total_difficulty: 0x78ed983323d,
        transactions: [],
        transactions_root: ~h[0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421],
        uncles: []
      }
  """
  def deserialize(params) do
    %__MODULE__{
      number: map(get_in(params, ["number"]), &Hex.decode_hex_number!/1),
      hash: map(get_in(params, ["hash"]), &Hex.decode_word!/1),
      parent_hash: map(get_in(params, ["parentHash"]), &Hex.decode_word!/1),
      nonce: map(get_in(params, ["nonce"]), &Hex.decode_hex_number!/1),
      sha3_uncles: map(get_in(params, ["sha3Uncles"]), &Hex.decode_word!/1),
      logs_bloom:
        map(get_in(params, ["logsBloom"]), fn hex ->
          Hex.decode_sized!(hex, 256, "invalid logs bloom")
        end),
      transactions_root: map(get_in(params, ["transactionsRoot"]), &Hex.decode_word!/1),
      state_root: map(get_in(params, ["stateRoot"]), &Hex.decode_word!/1),
      receipts_root: map(get_in(params, ["receiptsRoot"]), &Hex.decode_word!/1),
      miner: map(get_in(params, ["miner"]), &Hex.decode_address!/1),
      difficulty: map(get_in(params, ["difficulty"]), &Hex.decode_hex_number!/1),
      total_difficulty: map(get_in(params, ["totalDifficulty"]), &Hex.decode_hex_number!/1),
      extra_data: map(get_in(params, ["extraData"]), &Hex.decode_hex!/1),
      size: map(get_in(params, ["size"]), &Hex.decode_hex_number!/1),
      gas_limit: map(get_in(params, ["gasLimit"]), &Hex.decode_hex_number!/1),
      gas_used: map(get_in(params, ["gasUsed"]), &Hex.decode_hex_number!/1),
      timestamp: map(get_in(params, ["timestamp"]), &Hex.decode_hex_number!/1),
      # TODO
      transactions: [],
      uncles:
        map(get_in(params, ["uncles"]), fn uncles -> Enum.map(uncles, &Hex.decode_word!/1) end)
    }
  end

  defp map(x, f) do
    if is_nil(x), do: nil, else: f.(x)
  end
end

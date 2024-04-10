defmodule Signet.RPC do
  @moduledoc """
  Excessively simple RPC client for Ethereum.
  """
  use Signet.Hex

  require Logger

  import Signet.Util, only: [to_wei: 1]

  defp ethereum_node(), do: Signet.Application.ethereum_node()
  defp http_client(), do: Signet.Application.http_client()

  @default_gas_price nil
  @default_base_fee nil
  @default_base_fee_buffer 1.20
  @default_gas_buffer 1.50

  defp headers(extra_headers) do
    [
      {"Accept", "application/json"},
      {"Content-Type", "application/json"}
    ] ++ extra_headers
  end

  @doc false
  def get_body(method, params, id) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    }
  end

  # See https://blog.soliditylang.org/2021/04/21/custom-errors/
  defp decode_error(<<error_hash::binary-size(4), error_data::binary>>, errors)
       when is_list(errors) do
    all_errors = ["Panic(uint256)" | errors]

    case Enum.find(all_errors, fn error ->
           <<prefix::binary-size(4), _::binary>> = Signet.Hash.keccak(error)
           prefix == error_hash
         end) do
      nil ->
        :not_found

      error_abi ->
        params = ABI.decode(error_abi, error_data)

        # From https://blog.soliditylang.org/2020/10/28/solidity-0.8.x-preview/
        case {error_abi, params} do
          {"Panic(uint256)", [0x01]} ->
            {:ok, "assertion failure", nil}

          {"Panic(uint256)", [0x11]} ->
            {:ok, "arithmetic error: overflow or underflow", nil}

          {"Panic(uint256)", [0x12]} ->
            {:ok, "failed to convert value to enum", nil}

          {"Panic(uint256)", [0x21]} ->
            {:ok, "popped from empty array", nil}

          {"Panic(uint256)", [0x32]} ->
            {:ok, "out-of-bounds array access", nil}

          {"Panic(uint256)", [0x41]} ->
            {:ok, "out of memory", nil}

          {"Panic(uint256)", [0x51]} ->
            {:ok, "called a zero-initialized variable of internal function type", nil}

          _ ->
            {:ok, error_abi, params}
        end
    end
  end

  defp decode_error(_, _errors), do: :not_found

  defp decode_response(response, id, errors) do
    with {:ok, %{"jsonrpc" => "2.0", "result" => result, "id" => ^id}} <- Jason.decode(response) do
      {:ok, result}
    else
      {:ok,
       %{
         "jsonrpc" => "2.0",
         "error" => %{
           "code" => code = 3,
           "data" => data_hex,
           "message" => message
         },
         "id" => ^id
       }} ->
        extra_revert_data =
          case Hex.decode_hex(data_hex) do
            {:ok, data} ->
              case decode_error(data, errors) do
                {:ok, error_abi, error_params} when not is_nil(error_params) ->
                  %{error_abi: error_abi, error_params: error_params}

                _ ->
                  %{}
              end
              |> Enum.into(%{revert: data})

            _ ->
              %{}
          end

        {:error, Map.merge(%{code: code, message: message}, extra_revert_data)}

      {:ok,
       %{
         "jsonrpc" => "2.0",
         "error" => %{
           "code" => code,
           "message" => message
         },
         "id" => ^id
       }} ->
        {:error, %{code: code, message: message}}

      _ ->
        {:error, %{code: -999, message: "invalid JSON-RPC response"}}
    end
  end

  @doc """
  Simple RPC client for a JSON-RPC Ethereum node.

  ## Examples

      iex> Signet.RPC.send_rpc("net_version", [])
      {:ok, "3"}

      iex> use Signet.Hex
      iex> Signet.RPC.send_rpc("get_balance", ["0x407d73d8a49eeb85d32cf465507dd71d507100c1", "latest"], ethereum_node: "http://example.com")
      {:ok, "0x0234c8a3397aab58"}
  """
  @spec send_rpc(String.t(), [term()], Keyword.t()) ::
          {:ok, term()} | {:error, %{code: integer(), message: String.t()}}
  def send_rpc(method, params, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    decode = Keyword.get(opts, :decode, nil)
    errors = Keyword.get(opts, :errors, nil)
    timeout = Keyword.get(opts, :timeout, 30_000)
    verbose = Keyword.get(opts, :verbose, false)
    url = Keyword.get(opts, :ethereum_node, ethereum_node())
    id = Keyword.get_lazy(opts, :id, fn -> System.unique_integer([:positive]) end)
    body = get_body(method, params, id)

    case http_client().post(url, Jason.encode!(body), headers(headers), recv_timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} when code in 200..299 ->
        with {:ok, result} <- decode_response(resp_body, body["id"], errors) do
          case decode do
            nil ->
              {:ok, result}

            :hex ->
              Hex.decode_hex(result)

            :hex_unsigned ->
              with {:ok, bin} <- Hex.decode_hex(result) do
                {:ok, :binary.decode_unsigned(bin)}
              end

            f when is_function(f) ->
              try do
                {:ok, f.(result)}
              rescue
                e ->
                  if verbose do
                    Logger.error(
                      "[Signet][RPC][#{method}] Error decoding response. error=#{inspect(e)}, response=#{inspect(result)}"
                    )

                    {:error, "failed to decode `#{method}` response: #{inspect(e)}"}
                  else
                    Logger.info("[Signet][RPC][#{method}] Error decoding response: #{inspect(e)}")

                    {:error, "failed to decode `#{method}` response: #{inspect(e)}"}
                  end
              end
          end
        end

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "error: #{inspect(reason)}"}
    end
  end

  @doc """
  RPC call to get account nonce.

  ## Examples

      iex> use Signet.Hex
      iex> Signet.RPC.get_nonce(~h[0x407d73d8a49eeb85d32cf465507dd71d507100c1])
      {:ok, 4}
  """
  def get_nonce(account, opts \\ []) do
    block_number = Keyword.get(opts, :block_number, "latest")

    send_rpc(
      "eth_getTransactionCount",
      [Hex.encode_big_hex(account), block_number],
      Keyword.merge(opts, decode: :hex_unsigned)
    )
  end

  @doc """
  RPC call to send a raw transaction.

  ## Examples

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, signed_trx} = Signet.Transaction.build_signed_trx(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, 100_000, 0, chain_id: :goerli, signer: signer_proc)
      iex> {:ok, trx_id} = Signet.RPC.send_trx(signed_trx)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {5, 50000000000, 100000, <<1::160>>}

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, signed_trx} = Signet.Transaction.build_signed_trx_v2(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, {10, :gwei}, 100_000, 0, [], chain_id: :goerli, signer: signer_proc)
      iex> {:ok, trx_id} = Signet.RPC.send_trx(signed_trx)
      iex> <<nonce::integer-size(8), max_priority_fee_per_gas::integer-size(64), max_fee_per_gas::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, max_priority_fee_per_gas, max_fee_per_gas, gas_limit, to}
      {5, 50000000000, 10000000000, 100000, <<1::160>>}
  """
  def send_trx(trx, opts \\ [])

  def send_trx(trx = %Signet.Transaction.V1{}, opts) do
    send_rpc(
      "eth_sendRawTransaction",
      [Hex.encode_big_hex(Signet.Transaction.V1.encode(trx))],
      Keyword.merge(opts, decode: :hex)
    )
  end

  def send_trx(
        trx = %Signet.Transaction.V2{signature_y_parity: v, signature_r: r, signature_s: s},
        opts
      )
      when not is_nil(v) and not is_nil(r) and not is_nil(s) do
    send_rpc(
      "eth_sendRawTransaction",
      [Hex.encode_big_hex(Signet.Transaction.V2.encode(trx))],
      Keyword.merge(opts, decode: :hex)
    )
  end

  @doc ~S"""
  RPC call to call a transaction and preview results.

  ## Examples

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.call_trx()
      {:ok, <<0x0c>>}

      iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
      iex> |> Signet.RPC.call_trx()
      {:ok, <<0x0d>>}

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.call_trx(decode: :hex_unsigned)
      {:ok, 0x0c}

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.call_trx()
      {:error, %{code: 3, message: "execution reverted", revert: <<61, 115, 139, 46>>}}

      iex> errors = ["Unauthorized()", "BadNonce()", "NotEnoughSigners()", "NotActiveWithdrawalAddress()", "NotActiveOperator()", "DuplicateSigners()"]
      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.call_trx(errors: errors)
      {:error, %{code: 3, message: "execution reverted", error_abi: "NotActiveOperator()", error_params: [], revert: <<61, 115, 139, 46>>}}

      iex> errors = ["Cool(uint256,string)"]
      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.call_trx(errors: errors)
      {:error, %{code: 3, message: "execution reverted", error_abi: "Cool(uint256,string)", error_params: [1, "cat"], revert: ABI.encode("Cool(uint256,string)", [1, "cat"])}}

      iex> errors = ["Cool(uint256,string)"]
      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<12::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.call_trx(errors: errors)
      {:error, %{code: 3, message: "execution reverted", revert: <<>>}}
  """
  def call_trx(trx, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = Keyword.get(opts, :block_number, "latest")
    errors = Keyword.get(opts, :errors, [])

    send_rpc(
      "eth_call",
      [to_call_params(trx, from), block_number],
      opts
      |> Keyword.put_new(:decode, :hex)
      |> Keyword.put_new(:errors, errors)
    )
  end

  @doc """
  RPC call to call to estimate gas used by a given call.

  ## Examples

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.estimate_gas()
      {:ok, 0x0d}

      iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
      iex> |> Signet.RPC.estimate_gas()
      {:ok, 0xdd}

      iex> use Signet.Hex
      iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
      iex> |> Signet.RPC.estimate_gas()
      {:error, %{code: 3, message: "execution reverted: Dai/insufficient-balance", revert: ~h[0x08c379a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000184461692f696e73756666696369656e742d62616c616e63650000000000000000]}}
  """
  def estimate_gas(trx, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = Keyword.get(opts, :block_number, "latest")

    send_rpc(
      "eth_estimateGas",
      [to_call_params(trx, from), block_number],
      Keyword.merge(opts, decode: :hex_unsigned)
    )
  end

  @doc ~S"""
  RPC to get the current chain id.

  Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_chainid

  ## Examples

      iex> Signet.RPC.eth_chain_id()
      {:ok, 0x22}
  """
  def eth_chain_id(opts \\ []) do
    Signet.RPC.send_rpc("eth_chainId", [], Keyword.merge(opts, decode: :hex_unsigned))
  end

  @doc """
  RPC call to get code for a contract at an address.

  ## Examples

      iex> Signet.RPC.get_code(<<1::160>>)
      {:ok, <<0x11, 0x22, 0x33>>}
  """
  def get_code(address = <<_::160>>, opts \\ []) do
    block_number = Keyword.get(opts, :block_number, "latest")

    send_rpc(
      "eth_getCode",
      [Hex.encode_big_hex(address), block_number],
      Keyword.merge(opts, decode: :hex)
    )
  end

  @doc ~S"""
  RPC to get an account's eth balance.

  Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getbalance

  ## Examples

      iex> Signet.RPC.get_balance(~h[0x0000000000000000000000000000000000000001])
      {:ok, 0x55}
  """
  def get_balance(address = <<_::160>>, opts \\ []) do
    block_number = Keyword.get(opts, :block_number, "latest")

    Signet.RPC.send_rpc(
      "eth_getBalance",
      [to_hex(address), block_number],
      Keyword.merge(opts, decode: :hex_unsigned)
    )
  end

  @doc ~S"""
  RPC to get an account's transaction count (i.e. nonce)

  Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_gettransactioncount

  ## Examples

      iex> Signet.RPC.get_transaction_count(~h[0x0000000000000000000000000000000000000001])
      {:ok, 0x4}
  """
  def get_transaction_count(address = <<_::160>>, opts \\ []) do
    block_number = Keyword.get(opts, :block_number, "latest")

    Signet.RPC.send_rpc(
      "eth_getTransactionCount",
      [to_hex(address), block_number],
      Keyword.merge(opts, decode: :hex_unsigned)
    )
  end

  @doc ~S"""
  RPC to get the current block number.

  Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_blocknumber

  ## Examples

      iex> Signet.RPC.eth_block_number()
      {:ok, 0x44}
  """
  def eth_block_number(opts \\ []) do
    Signet.RPC.send_rpc("eth_blockNumber", [], Keyword.merge(opts, decode: :hex_unsigned))
  end

  @doc ~S"""
  RPC to get a block by its block number.

  Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getblockbynumber

  ## Examples

      iex> Signet.RPC.get_block_by_number(55)
      {:ok, %Signet.Block{
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
      }}
  """
  def get_block_by_number(block_number, opts \\ []) do
    send_rpc(
      "eth_getBlockByNumber",
      [block_number],
      Keyword.merge(opts, decode: &Signet.Block.deserialize/1)
    )
  end

  @doc ~S"""
  RPC to get a block by its block hash.

  Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getblockbyhash

  ## Examples

      iex> Signet.RPC.get_block_by_hash(~h[0xdc0818cf78f21a8e70579cb46a43643f78291264dda342ae31049421c82d21ae])
      {:ok, %Signet.Block{
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
      }}
  """
  def get_block_by_hash(block_hash, opts \\ []) do
    send_rpc(
      "eth_getBlockByHash",
      [to_hex(block_hash)],
      Keyword.merge(opts, decode: &Signet.Block.deserialize/1)
    )
  end

  @doc """
  RPC call to get a transaction receipt. Note, this will return {:ok, %Signet.Receipt{}} or {:ok, nil} if the
  receipt is not yet available.

  ## Examples

      iex> Signet.RPC.get_trx_receipt(~h[0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5])
      {:ok,
        %Signet.Receipt{
          transaction_hash: ~h[0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5],
          transaction_index: 0x66,
          block_hash: ~h[0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3],
          block_number: 0xeff35f,
          from: ~h[0x6221a9c005f6e47eb398fd867784cacfdcfff4e7],
          to: ~h[0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2],
          cumulative_gas_used: 0xa12515,
          effective_gas_price: 0x5a9c688d4,
          gas_used: 0xb4c8,
          contract_address: nil,
          logs: [
            %Signet.Receipt.Log{
              log_index: 1,
              block_number: 0x01b4,
              block_hash: ~h[0xaa8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcfdf829c5a142f1fccd7d],
              transaction_hash: ~h[0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf],
              transaction_index: 0,
              address: ~h[0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d],
              data: ~h[0x0000000000000000000000000000000000000000000000000000000000000000],
              topics: [
                ~h[0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5]
              ]
            }
          ],
          logs_bloom: ~h[0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001],
          type: 0x02,
          status: 0x01,
        }
      }

      iex> Signet.RPC.get_trx_receipt("0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5")
      {:ok,
        %Signet.Receipt{
          transaction_hash: ~h[0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5],
          transaction_index: 0x66,
          block_hash: ~h[0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3],
          block_number: 0xeff35f,
          from: ~h[0x6221a9c005f6e47eb398fd867784cacfdcfff4e7],
          to: ~h[0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2],
          cumulative_gas_used: 0xa12515,
          effective_gas_price: 0x5a9c688d4,
          gas_used: 0xb4c8,
          contract_address: nil,
          logs: [
            %Signet.Receipt.Log{
              log_index: 1,
              block_number: 0x01b4,
              block_hash: ~h[0xaa8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcfdf829c5a142f1fccd7d],
              transaction_hash: ~h[0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf],
              transaction_index: 0,
              address: ~h[0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d],
              data: ~h[0x0000000000000000000000000000000000000000000000000000000000000000],
              topics: [
                ~h[0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5]
              ]
            }
          ],
          logs_bloom: ~h[0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001],
          type: 0x02,
          status: 0x01,
        }
      }

      iex> Signet.RPC.get_trx_receipt("0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2")
      {:ok, %Signet.Receipt{
        transaction_hash: ~h[0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2],
        transaction_index: 0,
        block_hash: ~h[0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca],
        block_number: 10493428,
        from: ~h[0xb03d1100c68e58aa1895f8c1f230c0851ff41851],
        to: ~h[0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97],
        cumulative_gas_used: 222642,
        effective_gas_price: 1200000010,
        gas_used: 222642,
        contract_address: nil,
        logs: [
          %Signet.Receipt.Log{
            log_index: 0,
            block_number: 10493428,
            block_hash: ~h[0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca],
            transaction_hash: ~h[0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2],
            transaction_index: 0,
            address: ~h[0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97],
            data: ~h[0x000000000000000000000000cb372382aa9a9e6f926714f4305afac4566f75380000000000000000000000000000000000000000000000000000000000000000],
            topics: [
              ~h[0x3ffe5de331422c5ec98e2d9ced07156f640bb51e235ef956e50263d4b28d3ae4],
              ~h[0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d],
              ~h[0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d]
            ]
          },
          %Signet.Receipt.Log{
            log_index: 1,
            block_number: 10493428,
            block_hash: ~h[0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca],
            transaction_hash: ~h[0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2],
            transaction_index: 0,
            address: ~h[0xcb372382aa9a9e6f926714f4305afac4566f7538],
            data: ~h[0x0000000000000000000000000000000000000000000000000000000000000000],
            topics: [
              ~h[0xe0d20d95fbbe7375f6edead77b5ce5c5b096e7dac85848c45c37a95eaf17fe62],
              ~h[0x0000000000000000000000009d8ec03e9ddb71f04da9db1e38837aaac1782a97],
              ~h[0x00000000000000000000000054f0a87eb5c8c8ba70243de1ac19e735b41b10a2],
              ~h[0x0000000000000000000000000000000000000000000000000000000000000000]
            ]
          },
          %Signet.Receipt.Log{
            log_index: 2,
            block_number: 10493428,
            block_hash: ~h[0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca],
            transaction_hash: ~h[0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2],
            transaction_index: 0,
            address: ~h[0xcb372382aa9a9e6f926714f4305afac4566f7538],
            data: <<>>,
            topics: [
              ~h[0x0000000000000000000000000000000000000000000000000000000000000055]
            ]
          }
        ],
        logs_bloom: ~h[0x00800000000000000000000400000000000000000000000000000000000000000000000000000000000000000000002000200040000000000000000200001000000000000000000000000000000000000000000000000000000000000010000000008000020000004000000200000800000000000000000000220000000000000000000000000800000000000400000000000000000000000000000000000000000000040000000000008000008000000000000000000000000000000004000000800000000000004000000000000000000000000000000004080000000020000000000000000080000000000000000000000000000000000000000000000000],
        type: 0,
        status: 1
      }}

      iex> Signet.RPC.get_trx_receipt(<<1::256>>)
      {:error, "failed to decode `eth_getTransactionReceipt` response: %FunctionClauseError{module: Signet.Hex, function: :decode_hex_, arity: 1, kind: nil, args: nil, clauses: nil}"}

      iex> Signet.RPC.get_trx_receipt(<<1::256>>, verbose: true)
      {:error, "failed to decode `eth_getTransactionReceipt` response: %FunctionClauseError{module: Signet.Hex, function: :decode_hex_, arity: 1, kind: nil, args: nil, clauses: nil}"}

      iex> Signet.RPC.get_trx_receipt(<<2::256>>)
      {:ok, nil}
  """
  @spec get_trx_receipt(binary() | String.t(), Keyword.t()) ::
          {:ok, Signet.Receipt.t() | nil} | {:error, term()}
  def get_trx_receipt(trx_id, opts \\ [])

  def get_trx_receipt(trx_id = "0x" <> _, opts) when byte_size(trx_id) == 66,
    do: get_trx_receipt(Hex.from_hex!(trx_id), opts)

  def get_trx_receipt(trx_id = <<_::256>>, opts) do
    send_rpc(
      "eth_getTransactionReceipt",
      [Hex.encode_big_hex(trx_id)],
      Keyword.merge(opts,
        decode: fn
          nil ->
            nil

          receipt_params ->
            Signet.Receipt.deserialize(receipt_params)
        end
      )
    )
  end

  @doc """
  RPC call to get a transaction receipt

  ## Examples

      iex> Signet.RPC.trace_trx("0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5")
      {:ok,
        [
        %Signet.Trace{
          action: %Signet.Trace.Action{
            call_type: "call",
            from: ~h[0x83806d539d4ea1c140489a06660319c9a303f874],
            gas: 0x01a1f8,
            input: <<>>,
            to: ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750],
            value: 0x7a16c911b4d00000,
          },
          block_hash: ~h[0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add],
          block_number: 3068185,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]],
          transaction_hash: ~h[0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3],
          transaction_position: 2,
          type: "call"
        },
        %Signet.Trace{
          action: %Signet.Trace.Action{
            call_type: "call",
            from: ~h[0x83806d539d4ea1c140489a06660319c9a303f874],
            gas: 0x01a1f8,
            input: <<>>,
            to: ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750],
            value: 0x7a16c911b4d00000,
          },
          block_hash: ~h[0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add],
          block_number: 3068186,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]],
          transaction_hash: ~h[0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3],
          transaction_position: 2,
          type: "call"
        }
      ]}
  """
  def trace_trx(trx_id, opts \\ [])

  def trace_trx(trx_id = "0x" <> _, opts) when byte_size(trx_id) == 66,
    do: trace_trx(Hex.decode_hex!(trx_id), opts)

  def trace_trx(trx_id = <<_::256>>, opts) do
    send_rpc(
      "trace_transaction",
      [Hex.encode_big_hex(trx_id)],
      Keyword.merge(opts, decode: &Signet.Trace.deserialize_many/1)
    )
  end

  @doc """
  RPC to trace a transaction call speculatively.

  ## Examples

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      ...> |> Signet.RPC.trace_call()
      {:ok,
        [
        %Signet.Trace{
          action: %Signet.Trace.Action{
            call_type: "call",
            from: ~h[0x83806d539d4ea1c140489a06660319c9a303f874],
            gas: 0x01a1f8,
            input: <<>>,
            to: ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750],
            value: 0x7a16c911b4d00000,
          },
          block_hash: ~h[0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add],
          block_number: 3068185,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]],
          transaction_hash: ~h[0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3],
          transaction_position: 2,
          type: "call"
        },
        %Signet.Trace{
          action: %Signet.Trace.Action{
            call_type: "call",
            from: ~h[0x83806d539d4ea1c140489a06660319c9a303f874],
            gas: 0x01a1f8,
            input: <<>>,
            to: ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750],
            value: 0x7a16c911b4d00000,
          },
          block_hash: ~h[0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add],
          block_number: 3068186,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]],
          transaction_hash: ~h[0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3],
          transaction_position: 2,
          type: "call"
        }
      ]}

      iex> Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
      ...> |> Signet.RPC.trace_call()
      {:ok,
        [
        %Signet.Trace{
          action: %Signet.Trace.Action{
            call_type: "call",
            from: ~h[0x83806d539d4ea1c140489a06660319c9a303f874],
            gas: 0x01a1f8,
            input: <<>>,
            to: ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750],
            value: 0x7a16c911b4d00000,
          },
          block_hash: ~h[0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add],
          block_number: 3068185,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]],
          transaction_hash: ~h[0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3],
          transaction_position: 2,
          type: "call"
        },
        %Signet.Trace{
          action: %Signet.Trace.Action{
            call_type: "call",
            from: ~h[0x83806d539d4ea1c140489a06660319c9a303f874],
            gas: 0x01a1f8,
            input: <<>>,
            to: ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750],
            value: 0x7a16c911b4d00000,
          },
          block_hash: ~h[0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add],
          block_number: 3068186,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]],
          transaction_hash: ~h[0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3],
          transaction_position: 2,
          type: "call"
        }
      ]}
  """
  def trace_call(trx, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = Keyword.get(opts, :block_number, "latest")

    send_rpc(
      "trace_call",
      [to_call_params(trx, from), ["trace"], block_number],
      Keyword.merge(opts, decode: &Signet.Trace.deserialize_many/1)
    )
  end

  @doc """
  RPC to trace many transaction calls speculatively.

  ## Examples

      iex> t1 = Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> t2 = Signet.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
      iex> Signet.RPC.trace_call_many([t1, t2])
      {:ok, [
        %Signet.TraceCall{
          output: "",
          state_diff: nil,
          trace: [
            %Signet.Trace{
              action: %Signet.Trace.Action{
                call_type: "call",
                init: nil,
                from: <<0::160>>,
                gas: 499_978_072,
                input: ~h[0xd1692f56000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a6120000000000000000000000000000000000000000000000000000000000000000],
                to: ~h[0x13172EE393713FBA9925A9A752341EBD31E8D9A7],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 492_166_471,
              error: "Reverted",
              output: "",
              result_code: nil,
              result_address: nil,
              subtraces: 1,
              trace_address: [],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            },
            %Signet.Trace{
              action: %Signet.Trace.Action{
                call_type: nil,
                init: ~h[0x60e03461009157601f6101ec38819003918201601f19168301916001600160401b038311848410176100965780849260609460405283398101031261009157610047816100ac565b906100606040610059602084016100ac565b92016100ac565b9060805260a05260c05260405161012b90816100c18239608051816088015260a051816045015260c0518160c60152f35b600080fd5b634e487b7160e01b600052604160045260246000fd5b51906001600160a01b03821682036100915756fe608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03166080908152602090f35b600036818037808036817f00000000000000000000000000000000000000000000000000000000000000005af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c6343000817003300000000000000000000000049e5d261e95f6a02505078bb339fecb210a0b634000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612],
                from: ~h[0x13172EE393713FBA9925A9A752341EBD31E8D9A7],
                gas: 492_133_529,
                input: nil,
                to: nil,
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: nil,
              error: "contract address collision",
              output: nil,
              result_code: nil,
              result_address: nil,
              subtraces: 0,
              trace_address: [0],
              transaction_hash: nil,
              transaction_position: nil,
              type: "create"
            }
          ],
          vm_trace: nil
        },
        %Signet.TraceCall{
          output: ~h[0x00000000000000000000000079EDBC4F3A6AA2266CD469CC544501743BE8B078],
          state_diff: nil,
          trace: [
            %Signet.Trace{
              action: %Signet.Trace.Action{
                call_type: "call",
                init: nil,
                from: <<0::160>>,
                gas: 499_945_916,
                input: ~h[0xd6d38d3f0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000081a60808060405234610016576107fe908161001c8239f35b600080fdfe6040608081526004908136101561001557600080fd5b600091823560e01c80630c0a769b146102eb57806350a4548914610255578063c3da3590146100fc5763f1afb11f1461004d57600080fd5b8291346100f85760803660031901126100f857610068610389565b61007061039f565b6100786103b5565b6001600160a01b03908116929091606435918390610097848288610482565b1693843b156100f457879460649386928851998a978896634232cd6360e01b88521690860152602485015260448401525af19081156100eb57506100d85750f35b6100e1906103fc565b6100e85780f35b80fd5b513d84823e3d90fd5b8780fd5b5050fd5b503461025157606036600319011261025157610116610389565b67ffffffffffffffff929060243584811161024d5761013890369085016103cb565b9190946044359081116102495761015290369086016103cb565b9590928681036102395791958793926001600160a01b0380891693909290865b83811061017d578780f35b6101a88561019461018f848887610448565b61046e565b168c6101a184878c610448565b3591610482565b6101b661018f828685610448565b6101c182858a610448565b3590873b15610235578a51631e573fb760e31b81526001600160a01b03909116818d019081526020810192909252908990829081906040010381838b5af1801561022b57908991610217575b5050600101610172565b610220906103fc565b6100f457873861020d565b8a513d8b823e3d90fd5b8980fd5b845163b4fa3fb360e01b81528690fd5b8680fd5b8580fd5b8280fd5b50346102515760a03660031901126102515761026f610389565b9161027861039f565b6102806103b5565b906001600160a01b039060643582811691908290036102e6578288971693843b156100f457879460849385879389519a8b988997639032317760e01b895216908701521660248501526044840152833560648401525af19081156100eb57506100d85750f35b600080fd5b5090346102515760603660031901126102515782610307610389565b61030f61039f565b604435916001600160a01b03906103298482858516610482565b1690813b15610385578451631e573fb760e31b81526001600160a01b039091169581019586526020860192909252909384919082908490829060400103925af19081156100eb5750610379575080f35b610382906103fc565b80f35b8380fd5b600435906001600160a01b03821682036102e657565b602435906001600160a01b03821682036102e657565b604435906001600160a01b03821682036102e657565b9181601f840112156102e65782359167ffffffffffffffff83116102e6576020808501948460051b0101116102e657565b67ffffffffffffffff811161041057604052565b634e487b7160e01b600052604160045260246000fd5b90601f8019910116810190811067ffffffffffffffff82111761041057604052565b91908110156104585760051b0190565b634e487b7160e01b600052603260045260246000fd5b356001600160a01b03811681036102e65790565b60405163095ea7b360e01b602082018181526001600160a01b0385166024840152604480840196909652948252949390926104be606485610426565b83516000926001600160a01b039291858416918591829182855af1906104e26105a4565b82610572575b5081610567575b50156104ff575b50505050509050565b60405196602088015216602486015280604486015260448552608085019085821067ffffffffffffffff8311176105535750610548939461054391604052826105fc565b6105fc565b8038808080806104f6565b634e487b7160e01b81526041600452602490fd5b90503b1515386104ef565b8051919250811591821561058a575b505090386104e8565b61059d92506020809183010191016105e4565b3880610581565b3d156105df573d9067ffffffffffffffff821161041057604051916105d3601f8201601f191660200184610426565b82523d6000602084013e565b606090565b908160209103126102e6575180151581036102e65790565b60408051908101916001600160a01b031667ffffffffffffffff8311828410176104105761066c926040526000806020958685527f5361666545524332303a206c6f772d6c6576656c2063616c6c206661696c656487860152868151910182855af16106666105a4565b916106f4565b8051908282159283156106dc575b505050156106855750565b6084906040519062461bcd60e51b82526004820152602a60248201527f5361666545524332303a204552433230206f7065726174696f6e20646964206e6044820152691bdd081cdd58d8d9595960b21b6064820152fd5b6106ec93508201810191016105e4565b38828161067a565b919290156107565750815115610708575090565b3b156107115790565b60405162461bcd60e51b815260206004820152601d60248201527f416464726573733a2063616c6c20746f206e6f6e2d636f6e74726163740000006044820152606490fd5b8251909150156107695750805190602001fd5b6040519062461bcd60e51b82528160208060048301528251908160248401526000935b8285106107af575050604492506000838284010152601f80199101168101030190fd5b848101820151868601604401529381019385935061078c56fea264697066735822122065151e6cccce6828ff0901f46ab142cb8aa214fc37379817e3635a556dd638a564736f6c63430008170033000000000000],
                to: ~h[0x2926631647877E9A84BB7E3A0821D643BF8D63C0],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 4298,
              error: nil,
              output: ~h[0x00000000000000000000000079EDBC4F3A6AA2266CD469CC544501743BE8B078],
              result_code: nil,
              result_address: nil,
              subtraces: 0,
              trace_address: [],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            }
          ],
          vm_trace: nil
        },
        %Signet.TraceCall{
          output: <<130, 180, 41, 0>>,
          state_diff: nil,
          trace: [
            %Signet.Trace{
              action: %Signet.Trace.Action{
                call_type: "call",
                init: nil,
                from: <<0::160>>,
                gas: 499_977_072,
                input: ~h[0xdd560874000000000000000000000000000000000000000000000000000000000000000400000000000000000000000079edbc4f3a6aa2266cd469cc544501743be8b078000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000640c0a769b000000000000000000000000aec1f48e02cfb822be958b68c7957156eb3f0b6e0000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c723800000000000000000000000000000000000000000000000000000000000f429000000000000000000000000000000000000000000000000000000000],
                to: ~h[0x6E995746B61C48C5BDF58FC788B1AEA08DFB7E43],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 4202,
              error: "Reverted",
              output: ~h[0x82B42900],
              result_code: nil,
              result_address: nil,
              subtraces: 1,
              trace_address: [],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            },
            %Signet.Trace{
              action: %Signet.Trace.Action{
                call_type: "delegatecall",
                init: nil,
                from: ~h[0x6E995746B61C48C5BDF58FC788B1AEA08DFB7E43],
                gas: 492_162_171,
                input: ~h[0xdd560874000000000000000000000000000000000000000000000000000000000000000400000000000000000000000079edbc4f3a6aa2266cd469cc544501743be8b078000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000640c0a769b000000000000000000000000aec1f48e02cfb822be958b68c7957156eb3f0b6e0000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c723800000000000000000000000000000000000000000000000000000000000f429000000000000000000000000000000000000000000000000000000000],
                to: ~h[0x49E5D261E95F6A02505078BB339FECB210A0B634],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 1362,
              error: "Reverted",
              output: <<130, 180, 41, 0>>,
              result_code: nil,
              result_address: nil,
              subtraces: 1,
              trace_address: [0],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            },
            %Signet.Trace{
              action: %Signet.Trace.Action{
                call_type: "staticcall",
                init: nil,
                from: ~h[0x6E995746B61C48C5BDF58FC788B1AEA08DFB7E43],
                gas: 484_471_386,
                input: ~h[0xC34C08E5],
                to: ~h[0x6E995746B61C48C5BDF58FC788B1AEA08DFB7E43],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 190,
              error: nil,
              output: ~h[0x000000000000000000000000142DA9114E5A98E015AA95AFCA0585E84832A612],
              result_code: nil,
              result_address: nil,
              subtraces: 0,
              trace_address: [0, 0],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            }
          ],
          vm_trace: nil
        }
      ]}
  """
  def trace_call_many(trxs, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = Keyword.get(opts, :block_number, "latest")

    send_rpc(
      "trace_callMany",
      [
        Enum.map(
          trxs,
          fn
            {trx, from} -> [to_call_params(trx, from), ["trace"]]
            trx -> [to_call_params(trx, from), ["trace"]]
          end
        ),
        block_number
      ],
      Keyword.merge(opts, decode: &Signet.TraceCall.deserialize_many/1)
    )
  end

  @doc """
  RPC call to call to get the current gas price.

  ## Examples

      iex> Signet.RPC.gas_price()
      {:ok, 1000000000}
  """
  def gas_price(opts \\ []) do
    send_rpc(
      "eth_gasPrice",
      [],
      Keyword.merge(opts, decode: :hex_unsigned)
    )
  end

  @doc """
  RPC call to call to get the current max priority fee per gas.

  ## Examples

      iex> Signet.RPC.max_priority_fee_per_gas()
      {:ok, 1000000001}
  """
  def max_priority_fee_per_gas(opts \\ []) do
    send_rpc(
      "eth_maxPriorityFeePerGas",
      [],
      Keyword.merge(opts, decode: :hex_unsigned)
    )
  end

  @doc """
  RPC call to call to get the Eip-1559 fee history data.

  ## Examples

      iex> Signet.RPC.fee_history()
      {:ok, %Signet.FeeHistory{
        base_fee_per_gas: [20566340803, 20460504186, 19629790325, 19239635811, 19090900440, 19048391846],
        gas_used_ratio: [0.4794155666666667, 0.3375966, 0.42049746666666665, 0.4690773, 0.49109343333333333],
        oldest_block: 16607861,
        reward: [[1000000000, 1000000000, 1500000000], [1000000000, 1000000000, 2000000000], [1000000000, 1000000000, 1000000000], [780000000, 1000000000, 2000000000], [1000000000, 1000000000, 1500000000]]
      }}
  """
  def fee_history(opts \\ []) do
    block_count = Keyword.get(opts, :block_count, 1)
    newest_block = Keyword.get(opts, :newest_block, "latest")
    reward_percentiles = Keyword.get(opts, :reward_percentiles, [])

    send_rpc(
      "eth_feeHistory",
      [block_count, newest_block, reward_percentiles],
      Keyword.merge(opts, decode: &Signet.FeeHistory.deserialize/1)
    )
  end

  @doc """
  Helper function to work with other Signet modules to get a nonce, sign a transction, and prepare it to be submitted on-chain.

  If you need higher-level functionality, like manual nonce tracking, you may want to use the more granular function calls.

  Options:
    * `gas_price` - Set the gas price for a v1 (non-Eip1559) transaction, if nil, comes from `eth_gasPrice` (default `nil`) [note: only compatible with V1 transaction]
    * `base_fee` - Set the base price for the transaction, if nil, will use base gas price from `eth_feeHistory` (default `nil`) [note: only compatible with V2 transactions]
    * `base_fee_buffer` - Buffer for the gas price or base fee when estimating gas price. Ingored if `gas_price` (for v1) or `base_fee` (for v2) is specified directly (default: 1.2 = 120%)
    * `priority_fee` - Additional gas to send as a priority fee. (default: `{0, :gwei}`) [note: only compatible with V2 transactions]
    * `gas_limit` - Set the gas limit for the transaction (default: calls `eth_estimateGas`)
    * `gas_buffer` - Buffer if estimating gas limit (default: 1.5 = 150%)
    * `value` - Value to provide with transaction in wei (default: 0)
    * `nonce` - Nonce to send with transaction. (default: lookup via `eth_transactionCount`)
    * `verify` - Verify the function is likely to succeed (default: true)
    * `trx_type` - :v1 for V1 (pre-EIP-1559 transactions), :v2 for V2 (EIP-1559) transactions, and `nil` for auto-detect.

    Note: if we don't `verify`, then `estimateGas` will likely fail if the transaction were to fail.
          To prevent this, `gas_limit` should always be supplied when `verify` is set to false.

  ## Examples
      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx} = Signet.RPC.prepare_trx(<<1::160>>, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, gas_price: {50, :gwei}, nonce: 10, value: 0, signer: signer_proc)
      iex> %{trx|v: nil, r: nil, s: nil}
      %Signet.Transaction.V1{
        nonce: 10,
        gas_price: 50000000000,
        gas_limit: 20,
        to: <<1::160>>,
        value: 0,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>
      }

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx} = Signet.RPC.prepare_trx(<<1::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, signer: signer_proc)
      iex> %{trx|v: nil, r: nil, s: nil}
      %Signet.Transaction.V1{
        nonce: 4,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<1::160>>,
        value: 0,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>
      }

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx} = Signet.RPC.prepare_trx(<<1::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, signer: signer_proc)
      iex> %{trx|v: nil, r: nil, s: nil}
      %Signet.Transaction.V1{
        nonce: 10,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<1::160>>,
        value: 0,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>
      }

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> Signet.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, signer: signer_proc)
      {:error, %{code: 3, message: "execution reverted", revert: <<61, 115, 139, 46>>}}

      iex> # Set gas price directly
      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx} = Signet.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|v: nil, r: nil, s: nil}
      %Signet.Transaction.V1{
        nonce: 10,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<10::160>>,
        value: 0,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>
      }

      iex> # Default gas price v1
      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx} = Signet.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_limit: 100_000, trx_type: :v1, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|v: nil, r: nil, s: nil}
      %Signet.Transaction.V1{
        nonce: 10,
        gas_price: 1200000000,
        gas_limit: 100000,
        to: <<10::160>>,
        value: 0,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>
      }

      iex> # Default gas price v2
      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx} = Signet.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_limit: 100_000, trx_type: :v2, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|signature_y_parity: nil, signature_r: nil, signature_s: nil}
      %Signet.Transaction.V2{
        chain_id: 5,
        nonce: 10,
        gas_limit: 100000,
        destination: <<10::160>>,
        amount: 0,
        max_fee_per_gas: 25679608965,
        max_priority_fee_per_gas: 1000000001,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>,
        access_list: []
      }

      iex> # Default gas price (trx_type: nil)
      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx} = Signet.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|signature_y_parity: nil, signature_r: nil, signature_s: nil}
      %Signet.Transaction.V2{
        chain_id: 5,
        nonce: 10,
        gas_limit: 100000,
        destination: <<10::160>>,
        amount: 0,
        max_fee_per_gas: 25679608965,
        max_priority_fee_per_gas: 1000000001,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>,
        access_list: []
      }

      iex> # Set priority fee (v2)
      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx} = Signet.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, priority_fee: {3, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|signature_y_parity: nil, signature_r: nil, signature_s: nil}
      %Signet.Transaction.V2{
        chain_id: 5,
        nonce: 10,
        gas_limit: 100000,
        destination: <<10::160>>,
        amount: 0,
        max_fee_per_gas: 27679608964,
        max_priority_fee_per_gas: 3000000000,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>,
        access_list: []
      }

      iex> # Set base fee and priority fee (v2)
      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx} = Signet.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, base_fee: {1, :gwei}, priority_fee: {3, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|signature_y_parity: nil, signature_r: nil, signature_s: nil}
      %Signet.Transaction.V2{
        chain_id: 5,
        nonce: 10,
        gas_limit: 100000,
        destination: <<10::160>>,
        amount: 0,
        max_fee_per_gas: 4000000000,
        max_priority_fee_per_gas: 3000000000,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>,
        access_list: []
      }

      iex> # Sets chain id
      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx} = Signet.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, base_fee: {1, :gwei}, priority_fee: {3, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc, chain_id: 99)
      iex> %{trx|signature_y_parity: nil, signature_r: nil, signature_s: nil}
      %Signet.Transaction.V2{
        chain_id: 99,
        nonce: 10,
        gas_limit: 100000,
        destination: <<10::160>>,
        amount: 0,
        max_fee_per_gas: 4000000000,
        max_priority_fee_per_gas: 3000000000,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>,
        access_list: []
      }
  """
  def prepare_trx(contract, call_data, opts \\ []) do
    with {:ok, trx, _send_opts} <- prepare_trx_(contract, call_data, opts) do
      {:ok, trx}
    end
  end

  @doc false
  defp prepare_trx_(contract, call_data, opts) do
    {trx_type, opts} = Keyword.pop(opts, :trx_type, nil)
    {gas_price_user, opts} = Keyword.pop(opts, :gas_price, @default_gas_price)
    {base_fee_user, opts} = Keyword.pop(opts, :base_fee, @default_base_fee)
    {base_fee_buffer, opts} = Keyword.pop(opts, :base_fee_buffer, @default_base_fee_buffer)
    {priority_fee_user, opts} = Keyword.pop(opts, :priority_fee, nil)
    {gas_limit, opts} = Keyword.pop(opts, :gas_limit)
    {gas_buffer, opts} = Keyword.pop(opts, :gas_buffer, @default_gas_buffer)
    {value, opts} = Keyword.pop(opts, :value, 0)
    {nonce, opts} = Keyword.pop(opts, :nonce)
    {verify, opts} = Keyword.pop(opts, :verify, true)
    {access_list, opts} = Keyword.pop(opts, :access_list, [])
    {signer, opts} = Keyword.pop(opts, :signer, Signet.Signer.Default)

    signer_address = Signet.Signer.address(signer)
    chain_id = Keyword.get_lazy(opts, :chain_id, fn -> Signet.Signer.chain_id(signer) end)
    send_opts = Keyword.put_new(opts, :from, signer_address)

    # Determine the type of the transaction based on the gas inputs. This is complicated because
    # a) we don't want the user to specify what they want since it would break earlier clients,
    # and b) it should be obvious on the inputs, e.g. `gas_price` implies a V1 transaction,
    # while `base_fee` or `priority_fee` imply a V2 transaction, and c) we want to default
    # users to V2 transactions if nothing is specified.
    trx_type_result =
      case {trx_type, gas_price_user, base_fee_user, priority_fee_user} do
        # v1 specified
        {:v1, nil, nil, nil} ->
          v1_gas_parameters(nil, base_fee_buffer, send_opts)

        # surmise :v1 since gas_price is set but not v2 gas parameters
        {nil, gas_price, nil, nil} when not is_nil(gas_price) ->
          v1_gas_parameters(gas_price, base_fee_buffer, send_opts)

        # any valid :v2 combination
        {ty, nil, user_base_fee, user_priority_fee} when ty in [nil, :v2] ->
          v2_gas_parameters(user_base_fee, user_priority_fee, base_fee_buffer, send_opts)

        _ ->
          raise "mismatched transaction type and gas price settings"
      end

    estimate_and_verify = fn trx ->
      with {:ok, _} <- if(verify, do: call_trx(trx, opts), else: {:ok, nil}),
           {:ok, gas_limit} <-
             (case gas_limit do
                nil ->
                  with {:ok, limit} <- estimate_gas(trx, opts) do
                    {:ok, ceil(limit * gas_buffer)}
                  end

                els ->
                  {:ok, els}
              end) do
        {:ok, %{trx | gas_limit: gas_limit}}
      end
    end

    with {:ok, trx_type} <- trx_type_result,
         {:ok, nonce} <-
           if(!is_nil(nonce), do: {:ok, nonce}, else: get_nonce(signer_address, opts)),
         {:ok, trx} <-
           (case trx_type do
              {:v1, gas_price} ->
                Signet.Transaction.build_signed_trx(
                  contract,
                  nonce,
                  call_data,
                  gas_price,
                  gas_limit,
                  value,
                  signer: signer,
                  chain_id: chain_id,
                  callback: estimate_and_verify
                )

              {:v2, max_fee_per_gas, max_priority_fee_per_gas} ->
                Signet.Transaction.build_signed_trx_v2(
                  contract,
                  nonce,
                  call_data,
                  max_priority_fee_per_gas,
                  max_fee_per_gas,
                  gas_limit,
                  value,
                  access_list,
                  signer: signer,
                  chain_id: chain_id,
                  callback: estimate_and_verify
                )
            end) do
      {:ok, trx, send_opts}
    end
  end

  @doc """
  Helper function to work with other Signet modules to get a nonce, sign a transction, and transmit it to the network.

  If you need higher-level functionality, like manual nonce tracking, you may want to use the more granular function calls.

  Options:
    * `gas_price` - Set the base gas for the transaction, overrides all other gas prices listed below (default `nil`) [note: only compatible with V1 transaction]
    * `base_fee` - Set the base price for the transaction, if nil, will use base gas price from `eth_gasPrice` call (default `nil`) [note: only compatible with V2 transactions]
    * `base_fee_buffer` - Buffer for the gas price when estimating gas (default: 1.2 = 120%) [note: only compatible with V2 transactions]
    * `priority_fee` - Additional gas to send as a priority fee. (default: `{0, :gwei}`) [note: only compatible with V2 transactions]
    * `gas_limit` - Set the gas limit for the transaction (default: calls `eth_estimateGas`)
    * `gas_buffer` - Buffer if estimating gas limit (default: 1.5 = 150%)
    * `value` - Value to provide with transaction in wei (default: 0)
    * `nonce` - Nonce to send with transaction. (default: lookup via `eth_transactionCount`)
    * `verify` - Verify the function is likely to succeed (default: true)
    * `trx_type` - :v1 for V1 (pre-EIP-1559 transactions), :v2 for V2 (EIP-1559) transactions, and `nil` for auto-detect.

    Note: if we don't `verify`, then `estimateGas` will likely fail if the transaction were to fail.
          To prevent this, `gas_limit` should always be supplied when `verify` is set to false.

  ## Examples
      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx_id} = Signet.RPC.execute_trx(<<1::160>>, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, gas_price: {50, :gwei}, value: 0, signer: signer_proc)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {4, 50000000000, 20, <<1::160>>}

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> Signet.RPC.execute_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, signer: signer_proc)
      {:error, %{code: 3, message: "execution reverted", revert: <<61, 115, 139, 46>>}}

      iex> # Set base fee and priority fee (v2)
      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx_id} = Signet.RPC.execute_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, base_fee: {1, :gwei}, priority_fee: {3, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> <<nonce::integer-size(8), max_priority_fee_per_gas::integer-size(64), max_fee_per_gas::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, max_priority_fee_per_gas, max_fee_per_gas, gas_limit, to}
      {10, 3000000000, 4000000000, 100000, <<10::160>>}
  """
  def execute_trx(contract, call_data, opts \\ []) do
    with {:ok, trx, send_opts} <- prepare_trx_(contract, call_data, opts) do
      send_trx(trx, send_opts)
    end
  end

  @doc false
  def to_call_params(trx = %Signet.Transaction.V1{}, from) do
    %{
      from: nil_map(from, &Hex.encode_big_hex/1),
      to: nil_map(trx.to, &Hex.encode_big_hex/1),
      gasPrice: nil_map(trx.gas_price, &Hex.encode_short_hex/1),
      value: nil_map(trx.value, &Hex.encode_short_hex/1),
      data: nil_map(trx.data, &Hex.encode_short_hex/1)
    }
  end

  def to_call_params(trx = %Signet.Transaction.V2{}, from) do
    %{
      from: nil_map(from, &Hex.encode_big_hex/1),
      to: nil_map(trx.destination, &Hex.encode_big_hex/1),
      maxPriorityFeePerGas: nil_map(trx.max_priority_fee_per_gas, &Hex.encode_short_hex/1),
      maxFeePerGas: nil_map(trx.max_fee_per_gas, &Hex.encode_short_hex/1),
      value: nil_map(trx.amount, &Hex.encode_short_hex/1),
      data: nil_map(trx.data, &Hex.encode_big_hex/1)
    }
  end

  defp v1_gas_parameters(user_gas_price, buffer, rpc_opts) do
    gas_price_result =
      if is_nil(user_gas_price) do
        gas_price(rpc_opts)
      else
        {:ok, to_wei(user_gas_price)}
      end

    buffer_multiplier = if is_nil(user_gas_price), do: buffer, else: 1

    with {:ok, gas_price} <- gas_price_result do
      {:ok, {:v1, ceil(gas_price * buffer_multiplier)}}
    end
  end

  defp v2_gas_parameters(user_base_fee, user_priority_fee, buffer, rpc_opts) do
    base_fee_result =
      if is_nil(user_base_fee) do
        get_fee_history_base_fee(rpc_opts)
      else
        {:ok, to_wei(user_base_fee)}
      end

    max_priority_fee_per_gas_result =
      if is_nil(user_priority_fee) do
        max_priority_fee_per_gas(rpc_opts)
      else
        {:ok, to_wei(user_priority_fee)}
      end

    buffer_multiplier = if is_nil(user_base_fee), do: buffer, else: 1

    with {:ok, base_fee} <- base_fee_result,
         {:ok, max_priority_fee_per_gas} <- max_priority_fee_per_gas_result do
      {:ok,
       {:v2, ceil(base_fee * buffer_multiplier + max_priority_fee_per_gas),
        max_priority_fee_per_gas}}
    end
  end

  defp get_fee_history_base_fee(rpc_opts) do
    with {:ok, %Signet.FeeHistory{base_fee_per_gas: [fee_history_base_fee | _]}} <-
           fee_history(rpc_opts) do
      {:ok, fee_history_base_fee}
    else
      {:ok, _} ->
        {:error, "missing fee history"}

      err ->
        err
    end
  end

  defp nil_map(nil, _), do: nil
  defp nil_map(x, fun), do: fun.(x)
end

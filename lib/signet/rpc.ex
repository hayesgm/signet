defmodule Signet.RPC do
  @moduledoc """
  Excessively simple RPC client for Ethereum.
  """
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

  defp get_body(method, params) do
    id = System.unique_integer([:positive])

    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    }
  end

  # See https://blog.soliditylang.org/2021/04/21/custom-errors/
  defp decode_error(<<error_hash::binary-size(4), error_data::binary>>, errors) do
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
          case Signet.Util.decode_hex(data_hex) do
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
    body = get_body(method, params)

    case http_client().post(url, Jason.encode!(body), headers(headers), recv_timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: code, body: resp_body}} when code in 200..299 ->
        with {:ok, result} <- decode_response(resp_body, body["id"], errors) do
          case decode do
            nil ->
              {:ok, result}

            :hex ->
              Signet.Util.decode_hex(result)

            :hex_unsigned ->
              with {:ok, bin} <- Signet.Util.decode_hex(result) do
                {:ok, :binary.decode_unsigned(bin)}
              end

            f when is_function(f) ->
              try do
                {:ok, f.(result)}
              rescue
                e ->
                  if verbose do
                    Logger.error("[Signet][RPC][#{method}] Error decoding response. error=#{inspect(e)}, response=#{inspect(result)}")

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

      iex> Signet.RPC.get_nonce(Signet.Util.decode_hex!("0x407d73d8a49eeb85d32cf465507dd71d507100c1"))
      {:ok, 4}
  """
  def get_nonce(account, opts \\ []) do
    block_number = Keyword.get(opts, :block_number, "latest")

    send_rpc(
      "eth_getTransactionCount",
      [Signet.Util.encode_hex(account), block_number],
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
      [Signet.Util.encode_hex(Signet.Transaction.V1.encode(trx))],
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
      [Signet.Util.encode_hex(Signet.Transaction.V2.encode(trx))],
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

  @doc """
  RPC call to get a transaction receipt. Note, this will return {:ok, %Signet.Receipt{}} or {:ok, nil} if the
  receipt is not yet available.

  ## Examples

      iex> Signet.RPC.get_trx_receipt(Signet.Util.decode_hex!("0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5"))
      {:ok,
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
          logs_bloom: Signet.Util.decode_hex!("0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001"),
          type: 0x02,
          status: 0x01,
        }
      }

      iex> Signet.RPC.get_trx_receipt("0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5")
      {:ok,
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
          logs_bloom: Signet.Util.decode_hex!("0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001"),
          type: 0x02,
          status: 0x01,
        }
      }

      iex> Signet.RPC.get_trx_receipt("0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2")
      {:ok, %Signet.Receipt{
        transaction_hash: Signet.Util.decode_hex!("0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2"),
        transaction_index: 0,
        block_hash: Signet.Util.decode_hex!("0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca"),
        block_number: 10493428,
        from: Signet.Util.decode_hex!("0xb03d1100c68e58aa1895f8c1f230c0851ff41851"),
        to: Signet.Util.decode_hex!("0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97"),
        cumulative_gas_used: 222642,
        effective_gas_price: 1200000010,
        gas_used: 222642,
        contract_address: nil,
        logs: [
          %Signet.Receipt.Log{
            log_index: 0,
            block_number: 10493428,
            block_hash: Signet.Util.decode_hex!("0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca"),
            transaction_hash: Signet.Util.decode_hex!("0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2"),
            transaction_index: 0,
            address: Signet.Util.decode_hex!("0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97"),
            data: Signet.Util.decode_hex!("0x000000000000000000000000cb372382aa9a9e6f926714f4305afac4566f75380000000000000000000000000000000000000000000000000000000000000000"),
            topics: [
              Signet.Util.decode_hex!("0x3ffe5de331422c5ec98e2d9ced07156f640bb51e235ef956e50263d4b28d3ae4"),
              Signet.Util.decode_hex!("0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d"),
              Signet.Util.decode_hex!("0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d")
            ]
          },
          %Signet.Receipt.Log{
            log_index: 1,
            block_number: 10493428,
            block_hash: Signet.Util.decode_hex!("0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca"),
            transaction_hash: Signet.Util.decode_hex!("0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2"),
            transaction_index: 0,
            address: Signet.Util.decode_hex!("0xcb372382aa9a9e6f926714f4305afac4566f7538"),
            data: Signet.Util.decode_hex!("0x0000000000000000000000000000000000000000000000000000000000000000"),
            topics: [
              Signet.Util.decode_hex!("0xe0d20d95fbbe7375f6edead77b5ce5c5b096e7dac85848c45c37a95eaf17fe62"),
              Signet.Util.decode_hex!("0x0000000000000000000000009d8ec03e9ddb71f04da9db1e38837aaac1782a97"),
              Signet.Util.decode_hex!("0x00000000000000000000000054f0a87eb5c8c8ba70243de1ac19e735b41b10a2"),
              Signet.Util.decode_hex!("0x0000000000000000000000000000000000000000000000000000000000000000")
            ]
          },
          %Signet.Receipt.Log{
            log_index: 2,
            block_number: 10493428,
            block_hash: Signet.Util.decode_hex!("0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca"),
            transaction_hash: Signet.Util.decode_hex!("0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2"),
            transaction_index: 0,
            address: Signet.Util.decode_hex!("0xcb372382aa9a9e6f926714f4305afac4566f7538"),
            data: <<>>,
            topics: [
              Signet.Util.decode_hex!("0x0000000000000000000000000000000000000000000000000000000000000055")
            ]
          }
        ],
        logs_bloom: Signet.Util.decode_hex!("0x00800000000000000000000400000000000000000000000000000000000000000000000000000000000000000000002000200040000000000000000200001000000000000000000000000000000000000000000000000000000000000010000000008000020000004000000200000800000000000000000000220000000000000000000000000800000000000400000000000000000000000000000000000000000000040000000000008000008000000000000000000000000000000004000000800000000000004000000000000000000000000000000004080000000020000000000000000080000000000000000000000000000000000000000000000000"),
        type: 0,
        status: 1
      }}


      iex> Signet.RPC.get_trx_receipt(<<1::256>>)
      {:error, "failed to decode `eth_getTransactionReceipt` response: %FunctionClauseError{module: Signet.Util, function: :decode_hex, arity: 1, kind: nil, args: nil, clauses: nil}"}

      iex> Signet.RPC.get_trx_receipt(<<1::256>>, verbose: true)
      {:error, "failed to decode `eth_getTransactionReceipt` response: %FunctionClauseError{module: Signet.Util, function: :decode_hex, arity: 1, kind: nil, args: nil, clauses: nil}"}

      iex> Signet.RPC.get_trx_receipt(<<2::256>>)
      {:ok, nil}
  """
  @spec get_trx_receipt(binary() | String.t(), Keyword.t()) ::
          {:ok, Signet.Receipt.t() | nil} | {:error, term()}
  def get_trx_receipt(trx_id, opts \\ [])

  def get_trx_receipt(trx_id = "0x" <> _, opts) when byte_size(trx_id) == 66,
    do: get_trx_receipt(Signet.Util.decode_hex!(trx_id), opts)

  def get_trx_receipt(trx_id = <<_::256>>, opts) do
    send_rpc(
      "eth_getTransactionReceipt",
      [Signet.Util.encode_hex(trx_id)],
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
        },
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
          block_number: 3068186,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [Signet.Util.decode_hex!("0x1c39ba39e4735cb65978d4db400ddd70a72dc750")],
          transaction_hash: Signet.Util.decode_hex!("0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3"),
          transaction_position: 2,
          type: "call"
        }
      ]}
  """
  def trace_trx(trx_id, opts \\ [])

  def trace_trx(trx_id = "0x" <> _, opts) when byte_size(trx_id) == 66,
    do: trace_trx(Signet.Util.decode_hex!(trx_id), opts)

  def trace_trx(trx_id = <<_::256>>, opts) do
    send_rpc(
      "trace_transaction",
      [Signet.Util.encode_hex(trx_id)],
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
        },
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
          block_number: 3068186,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [Signet.Util.decode_hex!("0x1c39ba39e4735cb65978d4db400ddd70a72dc750")],
          transaction_hash: Signet.Util.decode_hex!("0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3"),
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
        },
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
          block_number: 3068186,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [Signet.Util.decode_hex!("0x1c39ba39e4735cb65978d4db400ddd70a72dc750")],
          transaction_hash: Signet.Util.decode_hex!("0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3"),
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

  defp to_call_params(trx = %Signet.Transaction.V1{}, from) do
    %{
      from: if(is_nil(from), do: nil, else: Signet.Util.encode_hex(from)),
      to: Signet.Util.encode_hex(trx.to),
      gasPrice: Signet.Util.encode_hex(trx.gas_price, true),
      value: Signet.Util.encode_hex(trx.value, true),
      data: Signet.Util.encode_hex(trx.data, true)
    }
  end

  defp to_call_params(trx = %Signet.Transaction.V2{}, from) do
    %{
      from: if(is_nil(from), do: nil, else: Signet.Util.encode_hex(from)),
      to: Signet.Util.encode_hex(trx.destination),
      maxPriorityFeePerGas: Signet.Util.encode_hex(trx.max_priority_fee_per_gas, true),
      maxFeePerGas: Signet.Util.encode_hex(trx.max_fee_per_gas, true),
      value: Signet.Util.encode_hex(trx.amount, true),
      data: Signet.Util.encode_hex(trx.data, true)
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
      {:ok, {:v2, ceil(base_fee * buffer_multiplier + max_priority_fee_per_gas), max_priority_fee_per_gas}}
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
end

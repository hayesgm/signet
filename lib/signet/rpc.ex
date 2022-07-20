defmodule Signet.RPC do
  @moduledoc """
  Excessively simple RPC client for Ethereum.
  """

  defp ethereum_node(), do: Signet.Application.ethereum_node()
  defp http_client(), do: Signet.Application.http_client()

  @default_gas_price {1, :gwei}
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
  defp decode_error(<<error_hash::binary-size(4), error_data::binary()>>, errors) do
    case Enum.find(errors, fn error ->
           <<prefix::binary-size(4), _::binary()>> = Signet.Hash.keccak(error)
           prefix == error_hash
         end) do
      nil ->
        :not_found

      error_abi ->
        params = ABI.decode(error_abi, error_data)
        {:ok, error_abi, params}
    end
  end

  defp decode_response(response, id, errors) do
    with {:ok, %{"jsonrpc" => "2.0", "result" => result, "id" => ^id}} <- Jason.decode(response) do
      {:ok, result}
    else
      {:ok,
       %{
         "jsonrpc" => "2.0",
         "error" => %{
           "code" => code,
           "data" => data_hex,
           "message" => message
         },
         "id" => ^id
       }} ->
        with {:ok, data} <- Signet.Util.decode_hex(data_hex),
             {:ok, error_abi, error_params} <- decode_error(data, errors) do
          # TODO: Try to clean up how this is shown, just a little.
          {:error, "error #{code}: #{message} (#{error_abi}#{inspect(error_params)})"}
        else
          _ ->
            {:error, "error #{code}: #{message} (#{data_hex})"}
        end

      {:ok,
       %{
         "jsonrpc" => "2.0",
         "error" => %{
           "code" => code,
           "message" => message
         },
         "id" => ^id
       }} ->
        {:error, "error #{code}: #{message}"}

      {:error, error} ->
        {:error, error}

      _ ->
        {:error, "invalid JSON-RPC response"}
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
  def send_rpc(method, params, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    decode = Keyword.get(opts, :decode, nil)
    errors = Keyword.get(opts, :errors, nil)
    url = Keyword.get(opts, :ethereum_node, ethereum_node())
    body = get_body(method, params)

    case http_client().post(url, Jason.encode!(body), headers(headers)) do
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
  """
  def send_trx(trx = %Signet.Transaction.V1{}, opts \\ []) do
    send_rpc(
      "eth_sendRawTransaction",
      [Signet.Util.encode_hex(Signet.Transaction.V1.encode(trx))],
      Keyword.merge(opts, decode: :hex)
    )
  end

  @doc ~S"""
  RPC call to call a transaction and preview results.

  ## Examples

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.call_trx()
      {:ok, <<0x0c>>}

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.call_trx()
      {:error, "error 3: execution reverted (0x3d738b2e)"}

      iex> errors = ["Unauthorized()", "BadNonce()", "NotEnoughSigners()", "NotActiveWithdrawalAddress()", "NotActiveOperator()", "DuplicateSigners()"]
      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.call_trx(errors: errors)
      {:error, "error 3: execution reverted (NotActiveOperator()[])"}

      iex> errors = ["Cool(uint256,string)"]
      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.call_trx(errors: errors)
      {:error, "error 3: execution reverted (Cool(uint256,string)[1, \"cat\"])"}
  """
  def call_trx(trx = %Signet.Transaction.V1{}, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = Keyword.get(opts, :block_number, "latest")
    errors = Keyword.get(opts, :errors, [])

    send_rpc(
      "eth_call",
      [
        %{
          from: if(is_nil(from), do: nil, else: Signet.Util.encode_hex(from)),
          to: Signet.Util.encode_hex(trx.to),
          gas: Signet.Util.encode_hex(trx.gas_limit, true),
          gasPrice: Signet.Util.encode_hex(trx.gas_price, true),
          value: Signet.Util.encode_hex(trx.value, true),
          data: Signet.Util.encode_hex(trx.data, true)
        },
        block_number
      ],
      Keyword.merge(opts,
        decode: :hex,
        errors: errors
      )
    )
  end

  @doc """
  RPC call to call to estimate gas used by a given call.

  ## Examples

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Signet.RPC.estimate_gas()
      {:ok, 0x0d}
  """
  def estimate_gas(trx = %Signet.Transaction.V1{}, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = Keyword.get(opts, :block_number, "latest")

    send_rpc(
      "eth_estimateGas",
      [
        %{
          from: if(is_nil(from), do: nil, else: Signet.Util.encode_hex(from)),
          to: Signet.Util.encode_hex(trx.to),
          gasPrice: Signet.Util.encode_hex(trx.gas_price, true),
          value: Signet.Util.encode_hex(trx.value, true),
          data: Signet.Util.encode_hex(trx.data, true)
        },
        block_number
      ],
      Keyword.merge(opts, decode: :hex_unsigned)
    )
  end

  @doc """
  Helper function to work with other Signet modules to get a nonce, sign a transction, and transmit it to the network.

  If you need higher-level functionality, like manual nonce tracking, you may want to use the more granular function calls.

  Options:
    * `gas_price` - Set the gas price for the transaction (default `{1, :gwei}`)
    * `gas_limit` - Set the gas limit for the transaction (default: calls `eth_estimateGas`)
    * `gas_buffer` - Buffer if estimating gas limit (default: 1.5 = 150%)
    * `value` - Value to provide with transaction in wei (default: 0)
    * `nonce` - Nonce to send with transaction. (default: lookup via `eth_transactionCount`)
    * `verify` - Verify the function is likely to succeed before submitting (default: true)

    Note: if we don't `verify`, then `estimateGas` will likely fail if the transaction were to fail.
          To prevent this, `gas_limit` should always be supplied when `verify` is set to false.

  ## Examples

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx_id} = Signet.RPC.execute_trx(<<1::160>>, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, gas_price: {50, :gwei}, value: 0, signer: signer_proc)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {4, 50000000000, 20, <<1::160>>}

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx_id} = Signet.RPC.execute_trx(<<1::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, signer: signer_proc)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {4, 50000000000, 100000, <<1::160>>}

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx_id} = Signet.RPC.execute_trx(<<1::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, signer: signer_proc)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {10, 50000000000, 100000, <<1::160>>}

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> Signet.RPC.execute_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, signer: signer_proc)
      {:error, "error 3: execution reverted (0x3d738b2e)"}

      iex> signer_proc = Signet.Test.Signer.start_signer()
      iex> {:ok, trx_id} = Signet.RPC.execute_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {10, 50000000000, 100000, <<10::160>>}
  """
  def execute_trx(contract, call_data, opts \\ []) do
    gas_price = Keyword.get(opts, :gas_price, @default_gas_price)
    gas_limit = Keyword.get(opts, :gas_limit)
    gas_buffer = Keyword.get(opts, :gas_buffer, @default_gas_buffer)
    value = Keyword.get(opts, :value, 0)
    nonce = Keyword.get(opts, :nonce)
    verify = Keyword.get(opts, :verify, true)
    signer = Keyword.get(opts, :signer, Signet.Signer.Default)

    signer_address = Signet.Signer.address(signer)
    chain_id = Signet.Signer.chain_id(signer)
    opts = Keyword.put_new(opts, :from, signer_address)

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

    with {:ok, nonce} <-
           if(!is_nil(nonce), do: {:ok, nonce}, else: get_nonce(signer_address, opts)),
         {:ok, trx} <-
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
           ),
         {:ok, tx_id} <- send_trx(trx, opts) do
      {:ok, tx_id}
    end
  end
end

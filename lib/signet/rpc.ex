defmodule Signet.RPC do
  @moduledoc """
  Excessively simple RPC client for Ethereum.
  """

  @http_client Application.get_env(:signet, :client)
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

      iex> Signet.RPC.send_rpc("http://example.com", "net_version", [])
      {:ok, "3"}

      iex> Signet.RPC.send_rpc("http://example.com", "get_balance", ["0x407d73d8a49eeb85d32cf465507dd71d507100c1", "latest"])
      {:ok, "0x0234c8a3397aab58"}
  """
  def send_rpc(url, method, params, opts \\ []) do
    headers = Keyword.get(opts, :headers, [])
    decode = Keyword.get(opts, :decode, nil)
    errors = Keyword.get(opts, :errors, nil)
    body = get_body(method, params)

    case @http_client.post(url, Jason.encode!(body), headers(headers)) do
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
    end
  end

  @doc """
  RPC call to get account nonce.

  ## Examples

      iex> Signet.RPC.get_nonce("http://example.com", Signet.Util.decode_hex!("0x407d73d8a49eeb85d32cf465507dd71d507100c1"))
      {:ok, 4}
  """
  def get_nonce(url, account, block_number \\ "latest") do
    send_rpc(url, "eth_getTransactionCount", [Signet.Util.encode_hex(account), block_number], decode: :hex_unsigned)
  end

  @doc """
  RPC call to send a raw transaction.

  ## Examples

      iex> signer_proc = SignetHelper.start_signer()
      iex> {:ok, signed_trx} = Signet.Transaction.build_signed_trx(signer_proc, <<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, 100_000, 0, 5)
      iex> {:ok, trx_id} = Signet.RPC.send_trx(signed_trx, "http://example.com")
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {5, 50000000000, 100000, <<1::160>>}
  """
  def send_trx(trx = %Signet.Transaction.V1{}, url) do
    send_rpc(url, "eth_sendRawTransaction", [Signet.Util.encode_hex(Signet.Transaction.V1.encode(trx))], decode: :hex)
  end

  @doc ~S"""
  RPC call to call a transaction and preview results.

  ## Examples

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
      iex> |> Signet.RPC.call_trx("http://example.com")
      {:ok, <<0x0c>>}

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
      iex> |> Signet.RPC.call_trx("http://example.com")
      {:error, "error 3: execution reverted (0x3d738b2e)"}

      iex> errors = ["Unauthorized()", "BadNonce()", "NotEnoughSigners()", "NotActiveWithdrawalAddress()", "NotActiveOperator()", "DuplicateSigners()"]
      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
      iex> |> Signet.RPC.call_trx("http://example.com", errors: errors)
      {:error, "error 3: execution reverted (NotActiveOperator()[])"}

      iex> errors = ["Cool(uint256,string)"]
      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
      iex> |> Signet.RPC.call_trx("http://example.com", errors: errors)
      {:error, "error 3: execution reverted (Cool(uint256,string)[1, \"cat\"])"}
  """
  def call_trx(trx = %Signet.Transaction.V1{}, url, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = Keyword.get(opts, :block_number, "latest")
    errors = Keyword.get(opts, :errors, [])

    send_rpc(
      url,
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
      decode: :hex,
      errors: errors
    )
  end

  @doc """
  RPC call to call to estimate gas used by a given call.

  ## Examples

      iex> Signet.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
      iex> |> Signet.RPC.estimate_gas("http://example.com")
      {:ok, 0x0d}
  """
  def estimate_gas(trx = %Signet.Transaction.V1{}, url, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = Keyword.get(opts, :block_number, "latest")

    send_rpc(
      url,
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
      decode: :hex_unsigned
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

      iex> signer_proc = SignetHelper.start_signer()
      iex> {:ok, trx_id} = Signet.RPC.execute_trx(signer_proc, "http://example.com", <<1::160>>, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, gas_price: {50, :gwei}, value: 0)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {4, 50000000000, 20, <<1::160>>}

      iex> signer_proc = SignetHelper.start_signer()
      iex> {:ok, trx_id} = Signet.RPC.execute_trx(signer_proc, "http://example.com", <<1::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {4, 50000000000, 100000, <<1::160>>}

      iex> signer_proc = SignetHelper.start_signer()
      iex> {:ok, trx_id} = Signet.RPC.execute_trx(signer_proc, "http://example.com", <<1::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {10, 50000000000, 100000, <<1::160>>}

      iex> signer_proc = SignetHelper.start_signer()
      iex> Signet.RPC.execute_trx(signer_proc, "http://example.com", <<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10)
      {:error, "error 3: execution reverted (0x3d738b2e)"}

      iex> signer_proc = SignetHelper.start_signer()
      iex> {:ok, trx_id} = Signet.RPC.execute_trx(signer_proc, "http://example.com", <<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {10, 50000000000, 100000, <<10::160>>}
  """
  def execute_trx(signer, url, contract, call_data, opts \\ []) do
    gas_price = Keyword.get(opts, :gas_price, @default_gas_price)
    gas_limit = Keyword.get(opts, :gas_limit)
    gas_buffer = Keyword.get(opts, :gas_buffer, @default_gas_buffer)
    value = Keyword.get(opts, :value, 0)
    nonce = Keyword.get(opts, :nonce)
    verify = Keyword.get(opts, :verify, true)

    signer_address = Signet.Signer.address(signer)
    chain_id = Signet.Signer.chain_id(signer)

    estimate_and_verify = fn trx ->
      with {:ok, _} <- if(verify, do: call_trx(trx, url, opts), else: {:ok, nil}),
           {:ok, gas_limit} <-
             (case gas_limit do
                nil ->
                  with {:ok, limit} <- estimate_gas(trx, url, opts) do
                    {:ok, ceil(limit * gas_buffer)}
                  end

                els ->
                  {:ok, els}
              end) do
        {:ok, %{trx | gas_limit: gas_limit}}
      end
    end

    with {:ok, nonce} <- if(!is_nil(nonce), do: {:ok, nonce}, else: get_nonce(url, signer_address)),
         {:ok, trx} <-
           Signet.Transaction.build_signed_trx(
             signer,
             contract,
             nonce,
             call_data,
             gas_price,
             gas_limit,
             value,
             chain_id,
             estimate_and_verify
           ),
         {:ok, tx_id} <- send_trx(trx, url) do
      {:ok, tx_id}
    end
  end
end

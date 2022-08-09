defmodule Signet.Test.Client do
  @moduledoc """
  A module for helping tests by providing responses without
  needing to connect to a real Etheruem node.
  """

  defp parse_request(body) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    } = body

    {method, params, id}
  end

  def post(_url, body, _headers, _opts) do
    {method, params, id} = parse_request(Jason.decode!(body))

    case apply(__MODULE__, String.to_atom(method), params) do
      {:error, error} ->
        return_body = Jason.encode!(%{"jsonrpc" => "2.0", "error" => error, "id" => id})
        {:ok, %HTTPoison.Response{status_code: 200, body: return_body}}

      {:ok, result} ->
        return_body = Jason.encode!(%{"jsonrpc" => "2.0", "result" => result, "id" => id})
        {:ok, %HTTPoison.Response{status_code: 200, body: return_body}}

      result ->
        return_body = Jason.encode!(%{"jsonrpc" => "2.0", "result" => result, "id" => id})
        {:ok, %HTTPoison.Response{status_code: 200, body: return_body}}
    end
  end

  def net_version() do
    "3"
  end

  def get_balance(_address, _block) do
    "0x0234c8a3397aab58"
  end

  def eth_getTransactionCount(_address, _block) do
    "0x4"
  end

  def eth_sendRawTransaction(trx_enc) do
    {:ok, trx} =
      trx_enc
      |> Signet.Util.decode_hex!()
      |> Signet.Transaction.V1.decode()

    %Signet.Transaction.V1{
      nonce: nonce,
      gas_price: gas_price,
      gas_limit: gas_limit,
      to: to,
      value: _value,
      data: _data,
      v: _v,
      r: _r,
      s: _s
    } = trx

    Signet.Util.encode_hex(
      <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24),
        to::binary>>
    )
  end

  # Call that fails with simple encoded error
  def eth_call(_trx = %{"to" => "0x000000000000000000000000000000000000000A"}, _block) do
    {:error,
     %{
       "code" => 3,
       "data" => "0x3d738b2e",
       "message" => "execution reverted"
     }}
  end

  # Call that fails with complex encoded error
  def eth_call(_trx = %{"to" => "0x000000000000000000000000000000000000000B"}, _block) do
    {:error,
     %{
       "code" => 3,
       "data" => Signet.Util.encode_hex(ABI.encode("Cool(uint256,string)", [1, "cat"])),
       "message" => "execution reverted"
     }}
  end

  # Call that works
  def eth_call(_trx = %{"to" => "0x0000000000000000000000000000000000000001"}, _block) do
    "0x0c"
  end

  # Call to Adaptor- don't care about response
  def eth_call(trx = %{"to" => "0x00000000000000000000000000000000000000CC"}, _block) do
    case trx["data"] do
      "0x8035F0CE" ->
        # String.slice(Signet.Util.encode_hex(Signet.Hash.keccak("push()")), 0, 10) ->
        "0x"

      "0x8D4D94A6" <> _ ->
        # String.slice(Signet.Util.encode_hex(Signet.Hash.keccak("withdraw(uint256,address,uint256,bytes32,bytes[])")), 0, 10)
        "0x"

      _ ->
        "0x0c"
    end
  end

  # Call els
  def eth_call(_trx = %{"to" => _}, _block) do
    "0xcc"
  end

  def eth_estimateGas(_trx, _block) do
    "0x0d"
  end

  def eth_newFilter(%{}) do
    "0xf11735"
  end

  def eth_getFilterChanges("0xf11735") do
    [
      %{
        address: "0xb5a5f22694352c15b00323844ad545abb2b11028",
        blockHash: "0x99e8663c7b6d8bba3c7627a17d774238eae3e793dee30008debb2699666657de",
        blockNumber: "0x5d12ab",
        data: "0x00000000000000000000000000000000000000000000000000000004a817c800",
        logIndex: "0x0",
        removed: false,
        topics: [
          "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
          "0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8",
          "0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea"
        ],
        transactionHash: "0xa74c2432c9cf7dbb875a385a2411fd8f13ca9ec12216864b1a1ead3c99de99cd",
        transactionIndex: "0x3"
      }
    ]
  end
end

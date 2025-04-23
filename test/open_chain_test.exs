defmodule Signet.OpenChainTest do
  use ExUnit.Case, async: true
  use Signet.Hex
  doctest Signet.OpenChain
  doctest Signet.OpenChain.Signatures
  doctest Signet.OpenChain.API

  defmodule TestClient do
    @lookup_success ~S"""
    {
      "ok": true,
      "result": {
        "event": {
          "0x08c379a0": []
        },
        "function": {
          "0x08c379a0": [
            {
              "name": "Error(string)",
              "filtered": false
            }
          ]
        }
      }
    }
    """

    def request(
          %Finch.Request{
            method: "GET",
            host: "example.com",
            path: "/open-chain/signature-database/v1/lookup"
          },
          _finch_name,
          _opts
        ) do
      {:ok, %Finch.Response{status: 200, body: @lookup_success}}
    end
  end
end

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

    def get(
          "https://example.com/open-chain/signature-database/v1/lookup?" <> _params,
          _headers,
          _opts
        ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: @lookup_success}}
    end
  end
end

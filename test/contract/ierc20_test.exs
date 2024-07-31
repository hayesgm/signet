defmodule Signet.Contract.IERC20Test do
  @moduledoc ~S"""
  # This test is for the IERC20 generated contract

  To regenerate the ierc20 contract, run:

  ```sh
  mix compile && mix signet.gen --out test/support --prefix signet/contract ./test/abi/IERC20.json
  ```
  """
  use ExUnit.Case, async: true
  use Signet.Hex
  doctest Signet.Contract.IERC20
  alias Signet.Contract.IERC20

  test "returns correct contract name" do
    assert IERC20.contract_name() == "IERC20"
  end

  test "correctly decodes event" do
    assert IERC20.decode_event(
             [
               ~h[0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef],
               ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
               ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
             ],
             ~h[0x00000000000000000000000000000000000000000000000000000004a817c800]
           ) ==
             {:ok, "Transfer",
              %{
                "value" => 20_000_000_000,
                "from" => ~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
                "to" => ~h[0x7795126b3ae468f44c901287de98594198ce38ea]
              }}
  end

  test "correctly decodes call" do
    assert IERC20.decode_call(~h[0x313CE567]) == {:ok, "decimals", []}
  end
end

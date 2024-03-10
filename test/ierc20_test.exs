defmodule Signet.Contract.IERC20Test do
  @moduledoc ~S"""
  # This test is for the IERC20 generated contract

  To regenerate the ierc20 contract, run:

  ```sh
  mix compile && mix signet.gen --out test/support --prefix signet/contract ./test/abi/IERC20.json
  ```
  """
  use ExUnit.Case, async: true
  doctest Signet.Contract.IERC20
  alias Signet.Contract.IERC20

  test "returns correct contract name" do
    assert IERC20.contract_name() == "IERC20"
  end
end

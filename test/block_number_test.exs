defmodule Signet.Contract.BlockNumberTest do
  @moduledoc ~S"""
  # This test is for the BlockNumber generated contract

  To regenerate the block number contract, run:

  ```sh
  mix compile && mix signet.gen --out test/support --prefix signet/contract ./test/abi/BlockNumber.json
  ```
  """
  use ExUnit.Case, async: true
  doctest Signet.Contract.BlockNumber
  alias Signet.Contract.BlockNumber

  test "returns correct contract name" do
    assert BlockNumber.contract_name() == "BlockNumber"
  end
end

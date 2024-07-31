defmodule Signet.Contract.RockTest do
  @moduledoc ~S"""
  # This test is for the Rock.sol generated contract

  To regenerate the rock contract, run:

  ```sh
  mix compile && mix signet.gen --out test/support --prefix signet/contract ./test/abi/Rock.json
  ```

  To regenerate the Rock.json file, run:

  ```
  solc test/abi/Rock.sol --combined-json abi,bin,bin-runtime > test/abi/Rock.json
  ```

  """
  use ExUnit.Case, async: true
  doctest Signet.Contract.Rock
  alias Signet.Contract.Rock
  use Signet.Hex

  test "returns correct contract name" do
    assert Rock.contract_name() == "Rock"
  end

  describe "jam" do
    test "exec_vm" do
      assert {:ok, {22, "Band on the Run"}} = Rock.exec_vm_jam(22)
    end

    test "exec_vm_raw" do
      assert {:ok, res} = Rock.exec_vm_jam_raw(22)

      assert to_hex(res) ==
               "0x" <>
                 "0000000000000000000000000000000000000000000000000000000000000020" <>
                 "0000000000000000000000000000000000000000000000000000000000000016" <>
                 "0000000000000000000000000000000000000000000000000000000000000040" <>
                 "000000000000000000000000000000000000000000000000000000000000000f" <>
                 "42616e64206f6e207468652052756e0000000000000000000000000000000000"
    end
  end

  describe "stumble" do
    test "exec_vm" do
      assert {:revert, "Stumble", [55]} = Rock.exec_vm_stumble_144e59d6()
    end

    test "exec_vm_raw" do
      assert {:revert,
              ~h[0xd331ba980000000000000000000000000000000000000000000000000000000000000037]} =
               Rock.exec_vm_stumble_144e59d6_raw()
    end
  end
end

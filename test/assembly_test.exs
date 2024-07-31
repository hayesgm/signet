defmodule Signet.AssemblyTest do
  use ExUnit.Case, async: true
  alias Signet.Assembly
  use Signet.Hex
  doctest Assembly


  describe "compile/1" do
    test "with jumps" do
      assert [
               {:push, 4, <<1, 2, 3, 4>>},
               {:push, 1, <<0>>},
               :mstore,
               :origin,
               {:jump_ptr, i},
               :jumpi,
               {:push, 1, <<0>>},
               {:push, 1, <<0>>},
               :return,
               {:jump_dest, i},
               {:push, 1, <<4>>},
               {:push, 1, <<28>>},
               :revert
             ] =
               Assembly.compile([
                 {:mstore, 0, 0x01020304},
                 {:if, :origin, {:revert, 28, 4}, {:return, 0, 0}}
               ])
    end
  end

  describe "build/1" do
    test "check origin" do
      assert to_hex(
               Assembly.build([
                 {:mstore, 0, 0x01020304},
                 {:if, :origin, {:revert, 28, 4}, {:return, 0, 0}}
               ])
             ) == "0x630102030460005232620000135760006000f35b6004601cfd"
    end
  end
end

defmodule Signet.Solana.ProgramsTest do
  use ExUnit.Case, async: true

  alias Signet.Solana.Programs

  describe "program addresses" do
    test "system_program is 32 zero bytes" do
      assert Programs.system_program() == <<0::256>>
    end

    test "all addresses are 32 bytes" do
      assert byte_size(Programs.system_program()) == 32
      assert byte_size(Programs.token_program()) == 32
      assert byte_size(Programs.token_2022_program()) == 32
      assert byte_size(Programs.ata_program()) == 32
      assert byte_size(Programs.compute_budget_program()) == 32
      assert byte_size(Programs.wrapped_sol_mint()) == 32
    end

    test "encode to known Base58 addresses" do
      assert Signet.Base58.encode(Programs.system_program()) ==
               "11111111111111111111111111111111"

      assert Signet.Base58.encode(Programs.token_program()) ==
               "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

      assert Signet.Base58.encode(Programs.token_2022_program()) ==
               "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

      assert Signet.Base58.encode(Programs.ata_program()) ==
               "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"

      assert Signet.Base58.encode(Programs.compute_budget_program()) ==
               "ComputeBudget111111111111111111111111111111"

      assert Signet.Base58.encode(Programs.wrapped_sol_mint()) ==
               "So11111111111111111111111111111111111111112"
    end

    test "system_program matches SystemProgram.program_id" do
      assert Programs.system_program() == Signet.Solana.SystemProgram.program_id()
    end
  end
end

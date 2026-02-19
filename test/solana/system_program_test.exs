defmodule Signet.Solana.SystemProgramTest do
  use ExUnit.Case, async: true
  doctest Signet.Solana.SystemProgram

  alias Signet.Solana.SystemProgram
  alias Signet.Solana.Transaction.AccountMeta

  describe "program_id/0" do
    test "returns 32 zero bytes" do
      assert SystemProgram.program_id() == <<0::256>>
    end

    test "encodes to known Base58 address" do
      assert Signet.Base58.encode(SystemProgram.program_id()) ==
               "11111111111111111111111111111111"
    end
  end

  describe "transfer/3" do
    test "instruction data: index 2 + lamports (little-endian)" do
      ix = SystemProgram.transfer(<<1::256>>, <<2::256>>, 1_000_000_000)

      <<index::little-unsigned-32, lamports::little-unsigned-64>> = ix.data
      assert index == 2
      assert lamports == 1_000_000_000
    end

    test "instruction data for zero lamports" do
      ix = SystemProgram.transfer(<<1::256>>, <<2::256>>, 0)

      <<index::little-unsigned-32, lamports::little-unsigned-64>> = ix.data
      assert index == 2
      assert lamports == 0
    end

    test "instruction data for large amount" do
      ix = SystemProgram.transfer(<<1::256>>, <<2::256>>, 10_000_000_000_000)

      <<index::little-unsigned-32, lamports::little-unsigned-64>> = ix.data
      assert index == 2
      assert lamports == 10_000_000_000_000
    end

    test "accounts: from is writable signer, to is writable non-signer" do
      from = <<1::256>>
      to = <<2::256>>
      ix = SystemProgram.transfer(from, to, 100)

      assert [from_meta, to_meta] = ix.accounts
      assert from_meta == %AccountMeta{pubkey: from, is_signer: true, is_writable: true}
      assert to_meta == %AccountMeta{pubkey: to, is_signer: false, is_writable: true}
    end

    test "program_id is system program" do
      ix = SystemProgram.transfer(<<1::256>>, <<2::256>>, 100)
      assert ix.program_id == <<0::256>>
    end
  end

  describe "create_account/5" do
    test "instruction data: index 0 + lamports + space + owner" do
      owner = <<99::256>>

      ix =
        SystemProgram.create_account(<<1::256>>, <<2::256>>, 1_461_600, 165, owner)

      <<index::little-unsigned-32, lamports::little-unsigned-64, space::little-unsigned-64,
        decoded_owner::binary-32>> = ix.data

      assert index == 0
      assert lamports == 1_461_600
      assert space == 165
      assert decoded_owner == owner
    end

    test "accounts: both from and new_account are writable signers" do
      from = <<1::256>>
      new_acct = <<2::256>>
      ix = SystemProgram.create_account(from, new_acct, 100, 0, <<3::256>>)

      assert [from_meta, new_meta] = ix.accounts
      assert from_meta == %AccountMeta{pubkey: from, is_signer: true, is_writable: true}
      assert new_meta == %AccountMeta{pubkey: new_acct, is_signer: true, is_writable: true}
    end

    test "program_id is system program" do
      ix = SystemProgram.create_account(<<1::256>>, <<2::256>>, 100, 0, <<3::256>>)
      assert ix.program_id == <<0::256>>
    end

    test "data size is exactly 52 bytes" do
      ix = SystemProgram.create_account(<<1::256>>, <<2::256>>, 100, 0, <<3::256>>)
      # 4 (index) + 8 (lamports) + 8 (space) + 32 (owner) = 52
      assert byte_size(ix.data) == 52
    end
  end
end

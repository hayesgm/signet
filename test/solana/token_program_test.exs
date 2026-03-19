defmodule Signet.Solana.TokenProgramTest do
  use ExUnit.Case, async: true
  doctest Signet.Solana.TokenProgram

  alias Signet.Solana.TokenProgram
  alias Signet.Solana.Transaction.AccountMeta
  alias Signet.Solana.Programs

  @source <<1::256>>
  @destination <<2::256>>
  @authority <<3::256>>
  @mint <<4::256>>
  @delegate <<5::256>>

  describe "transfer/5" do
    test "correct data encoding" do
      ix = TokenProgram.transfer(@source, @destination, @authority, 1_000_000)
      assert ix.data == <<3, 64, 66, 15, 0, 0, 0, 0, 0>>

      <<index, amount::little-unsigned-64>> = ix.data
      assert index == 3
      assert amount == 1_000_000
    end

    test "correct accounts" do
      ix = TokenProgram.transfer(@source, @destination, @authority, 100)

      assert ix.accounts == [
               %AccountMeta{pubkey: @source, is_signer: false, is_writable: true},
               %AccountMeta{pubkey: @destination, is_signer: false, is_writable: true},
               %AccountMeta{pubkey: @authority, is_signer: true, is_writable: false}
             ]
    end

    test "uses SPL Token program by default" do
      ix = TokenProgram.transfer(@source, @destination, @authority, 100)
      assert ix.program_id == Programs.token_program()
    end

    test "token_program option" do
      ix =
        TokenProgram.transfer(@source, @destination, @authority, 100,
          token_program: Programs.token_2022_program()
        )

      assert ix.program_id == Programs.token_2022_program()
    end

    test "zero amount" do
      ix = TokenProgram.transfer(@source, @destination, @authority, 0)
      <<3, amount::little-unsigned-64>> = ix.data
      assert amount == 0
    end

    test "large amount" do
      ix = TokenProgram.transfer(@source, @destination, @authority, 18_446_744_073_709_551_615)
      <<3, amount::little-unsigned-64>> = ix.data
      assert amount == 18_446_744_073_709_551_615
    end
  end

  describe "transfer_checked/7" do
    test "correct data encoding" do
      ix = TokenProgram.transfer_checked(@source, @mint, @destination, @authority, 1_000_000, 6)

      <<index, amount::little-unsigned-64, decimals::unsigned-8>> = ix.data
      assert index == 12
      assert amount == 1_000_000
      assert decimals == 6
    end

    test "correct accounts include mint" do
      ix = TokenProgram.transfer_checked(@source, @mint, @destination, @authority, 100, 9)

      assert ix.accounts == [
               %AccountMeta{pubkey: @source, is_signer: false, is_writable: true},
               %AccountMeta{pubkey: @mint, is_signer: false, is_writable: false},
               %AccountMeta{pubkey: @destination, is_signer: false, is_writable: true},
               %AccountMeta{pubkey: @authority, is_signer: true, is_writable: false}
             ]
    end

    test "data size is exactly 10 bytes" do
      ix = TokenProgram.transfer_checked(@source, @mint, @destination, @authority, 100, 6)
      assert byte_size(ix.data) == 10
    end
  end

  describe "approve/5" do
    test "correct data encoding" do
      ix = TokenProgram.approve(@source, @delegate, @authority, 500_000)

      <<index, amount::little-unsigned-64>> = ix.data
      assert index == 4
      assert amount == 500_000
    end

    test "correct accounts" do
      ix = TokenProgram.approve(@source, @delegate, @authority, 100)

      assert ix.accounts == [
               %AccountMeta{pubkey: @source, is_signer: false, is_writable: true},
               %AccountMeta{pubkey: @delegate, is_signer: false, is_writable: false},
               %AccountMeta{pubkey: @authority, is_signer: true, is_writable: false}
             ]
    end
  end

  describe "close_account/4" do
    test "correct data encoding" do
      ix = TokenProgram.close_account(@source, @destination, @authority)
      assert ix.data == <<9>>
    end

    test "correct accounts" do
      ix = TokenProgram.close_account(@source, @destination, @authority)

      assert ix.accounts == [
               %AccountMeta{pubkey: @source, is_signer: false, is_writable: true},
               %AccountMeta{pubkey: @destination, is_signer: false, is_writable: true},
               %AccountMeta{pubkey: @authority, is_signer: true, is_writable: false}
             ]
    end
  end

  describe "sync_native/2" do
    test "correct data encoding" do
      ix = TokenProgram.sync_native(@source)
      assert ix.data == <<17>>
    end

    test "correct accounts" do
      ix = TokenProgram.sync_native(@source)

      assert ix.accounts == [
               %AccountMeta{pubkey: @source, is_signer: false, is_writable: true}
             ]
    end
  end
end

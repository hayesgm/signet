defmodule Signet.Solana.ATATest do
  use ExUnit.Case, async: true
  use Signet.Base58
  doctest Signet.Solana.ATA

  alias Signet.Solana.{ATA, PDA, Programs}
  alias Signet.Solana.Transaction.{AccountMeta}

  @wallet elem(Signet.Solana.Keys.from_seed(<<1::256>>), 0)
  @mint Programs.wrapped_sol_mint()

  describe "find_address/3" do
    test "returns 32-byte address and valid bump" do
      {ata, bump} = ATA.find_address(@wallet, @mint)
      assert byte_size(ata) == 32
      assert bump >= 0 and bump <= 255
    end

    test "is deterministic" do
      assert ATA.find_address(@wallet, @mint) == ATA.find_address(@wallet, @mint)
    end

    test "matches manual PDA derivation" do
      {ata_via_module, bump_via_module} = ATA.find_address(@wallet, @mint)

      {:ok, {ata_manual, bump_manual}} =
        PDA.find_program_address(
          [@wallet, Programs.token_program(), @mint],
          Programs.ata_program()
        )

      assert ata_via_module == ata_manual
      assert bump_via_module == bump_manual
    end

    test "different wallets produce different ATAs" do
      {pub2, _} = Signet.Solana.Keys.from_seed(<<2::256>>)
      {ata1, _} = ATA.find_address(@wallet, @mint)
      {ata2, _} = ATA.find_address(pub2, @mint)
      assert ata1 != ata2
    end

    test "different mints produce different ATAs" do
      fake_mint = <<99::256>>
      {ata1, _} = ATA.find_address(@wallet, @mint)
      {ata2, _} = ATA.find_address(@wallet, fake_mint)
      assert ata1 != ata2
    end

    test "token_program option changes the ATA" do
      {ata_default, _} = ATA.find_address(@wallet, @mint)
      {ata_2022, _} = ATA.find_address(@wallet, @mint, token_program: Programs.token_2022_program())
      assert ata_default != ata_2022
    end

    test "ATA address is not on curve" do
      {ata, _} = ATA.find_address(@wallet, @mint)
      refute PDA.on_curve?(ata)
    end
  end

  describe "create/4" do
    test "builds correct instruction" do
      payer = <<10::256>>
      ix = ATA.create(payer, @wallet, @mint)

      {expected_ata, _} = ATA.find_address(@wallet, @mint)

      assert ix.program_id == Programs.ata_program()
      assert ix.data == <<0>>

      assert ix.accounts == [
               %AccountMeta{pubkey: payer, is_signer: true, is_writable: true},
               %AccountMeta{pubkey: expected_ata, is_signer: false, is_writable: true},
               %AccountMeta{pubkey: @wallet, is_signer: false, is_writable: false},
               %AccountMeta{pubkey: @mint, is_signer: false, is_writable: false},
               %AccountMeta{pubkey: Programs.system_program(), is_signer: false, is_writable: false},
               %AccountMeta{pubkey: Programs.token_program(), is_signer: false, is_writable: false}
             ]
    end
  end

  describe "create_idempotent/4" do
    test "uses instruction index 1" do
      payer = <<10::256>>
      ix = ATA.create_idempotent(payer, @wallet, @mint)
      assert ix.data == <<1>>
    end

    test "has same accounts as create" do
      payer = <<10::256>>
      create_ix = ATA.create(payer, @wallet, @mint)
      idempotent_ix = ATA.create_idempotent(payer, @wallet, @mint)
      assert create_ix.accounts == idempotent_ix.accounts
      assert create_ix.program_id == idempotent_ix.program_id
    end

    test "token_2022 option changes the token program account" do
      payer = <<10::256>>
      ix_default = ATA.create_idempotent(payer, @wallet, @mint)
      ix_2022 = ATA.create_idempotent(payer, @wallet, @mint, token_program: Programs.token_2022_program())

      # Last account is the token program
      default_token_prog = List.last(ix_default.accounts).pubkey
      t2022_token_prog = List.last(ix_2022.accounts).pubkey

      assert default_token_prog == Programs.token_program()
      assert t2022_token_prog == Programs.token_2022_program()
    end
  end
end

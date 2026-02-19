defmodule Signet.Solana.TokenTest do
  use ExUnit.Case

  alias Signet.Solana.{Token, ATA, Programs}

  setup do
    prev_client = Application.get_env(:signet, :client)
    prev_node = Application.get_env(:signet, :solana_node)

    Application.put_env(:signet, :client, Signet.Solana.Test.Client)
    Application.put_env(:signet, :solana_node, "https://api.devnet.solana.com")

    on_exit(fn ->
      if prev_client,
        do: Application.put_env(:signet, :client, prev_client),
        else: Application.delete_env(:signet, :client)

      if prev_node,
        do: Application.put_env(:signet, :solana_node, prev_node),
        else: Application.delete_env(:signet, :solana_node)
    end)

    :ok
  end

  @wallet elem(Signet.Solana.Keys.from_seed(<<0::256>>), 0)
  @mint Signet.Base58.decode!("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

  describe "get_balance/3" do
    test "returns balance from mock" do
      assert Token.get_balance(@wallet, @mint) ==
               {:ok,
                %{
                  amount: 1_500_000_000,
                  decimals: 6,
                  mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
                }}
    end
  end

  describe "get_all_balances/2" do
    test "returns balances from both token programs" do
      assert {:ok, balances} = Token.get_all_balances(@wallet)

      # Should have 2 from Token Program + 1 from Token-2022
      assert length(balances) == 3

      # First two from SPL Token
      assert Enum.at(balances, 0) == %{
               mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
               amount: 1_500_000_000,
               decimals: 6,
               token_account: "AyVfCw5fBuVTkzG4bBPiDfCkuS1YGrh2i6pRgLHMwmZr"
             }

      assert Enum.at(balances, 1) == %{
               mint: "So11111111111111111111111111111111111111112",
               amount: 5_000_000_000,
               decimals: 9,
               token_account: "BzVfCw5fBuVTkzG4bBPiDfCkuS1YGrh2i6pRgLHMwmZs"
             }

      # Third from Token-2022
      assert Enum.at(balances, 2) == %{
               mint: "2DEy3MN8J2zKWVoYTPKg4wifoDBavX6XpSgbRsfuLAMn",
               amount: 999_000_000_000,
               decimals: 9,
               token_account: "CzVfCw5fBuVTkzG4bBPiDfCkuS1YGrh2i6pRgLHMwmZt"
             }
    end

    test "with include_token_2022: false only returns SPL Token" do
      assert {:ok, balances} = Token.get_all_balances(@wallet, include_token_2022: false)
      assert length(balances) == 2
    end
  end

  describe "transfer_instructions/6" do
    test "returns create_idempotent + transfer_checked instructions" do
      from_wallet = <<1::256>>
      to_wallet = <<2::256>>
      mint = <<3::256>>

      [create_ix, transfer_ix] =
        Token.transfer_instructions(from_wallet, to_wallet, mint, 1_000_000, 6)

      # First instruction: create idempotent ATA for destination
      {expected_to_ata, _} = ATA.find_address(to_wallet, mint)
      assert create_ix.program_id == Programs.ata_program()
      assert create_ix.data == <<1>>
      assert Enum.at(create_ix.accounts, 1).pubkey == expected_to_ata

      # Second instruction: transfer_checked
      {expected_from_ata, _} = ATA.find_address(from_wallet, mint)
      assert transfer_ix.program_id == Programs.token_program()

      <<12, amount::little-unsigned-64, decimals::unsigned-8>> = transfer_ix.data
      assert amount == 1_000_000
      assert decimals == 6

      assert Enum.at(transfer_ix.accounts, 0).pubkey == expected_from_ata
      assert Enum.at(transfer_ix.accounts, 1).pubkey == mint
      assert Enum.at(transfer_ix.accounts, 2).pubkey == expected_to_ata
      assert Enum.at(transfer_ix.accounts, 3).pubkey == from_wallet
    end

    test "token_2022 option propagates to both instructions" do
      from_wallet = <<1::256>>
      to_wallet = <<2::256>>
      mint = <<3::256>>

      [create_ix, transfer_ix] =
        Token.transfer_instructions(from_wallet, to_wallet, mint, 100, 9,
          token_program: Programs.token_2022_program()
        )

      # ATA create should use Token-2022 as the token program account
      assert List.last(create_ix.accounts).pubkey == Programs.token_2022_program()

      # Transfer should use Token-2022 program ID
      assert transfer_ix.program_id == Programs.token_2022_program()
    end
  end
end

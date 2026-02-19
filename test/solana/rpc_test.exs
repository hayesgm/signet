defmodule Signet.Solana.RPCTest do
  use ExUnit.Case

  alias Signet.Solana.RPC

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

  # Known test pubkeys
  @test_pubkey elem(Signet.Solana.Keys.from_seed(<<0::256>>), 0)
  @nonexistent_pubkey Signet.Base58.decode!("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
  @error_pubkey Signet.Base58.decode!("11111111111111111111111111111112")

  # Known blockhash from mock
  @mock_blockhash Signet.Base58.decode!("4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn")

  # ---------------------------------------------------------------------------
  # Core transport
  # ---------------------------------------------------------------------------

  describe "send_rpc/3" do
    test "returns raw result" do
      assert RPC.send_rpc("getSlot", []) == {:ok, 256_000}
    end

    test "returns error for unknown method" do
      assert {:error, %{code: -32601, message: "Method not found: bogusMethod"}} =
               RPC.send_rpc("bogusMethod", [])
    end
  end

  # ---------------------------------------------------------------------------
  # Account methods
  # ---------------------------------------------------------------------------

  describe "get_balance/2" do
    test "returns lamport balance" do
      assert RPC.get_balance(@test_pubkey) == {:ok, 1_500_000_000}
    end

    test "returns error for error address" do
      assert {:error, %{code: -32600, message: "Invalid request"}} =
               RPC.get_balance(@error_pubkey)
    end
  end

  describe "get_account_info/2" do
    test "returns deserialized account info" do
      assert RPC.get_account_info(@test_pubkey) ==
               {:ok,
                %{
                  data: ["AQAAAAA=", "base64"],
                  executable: false,
                  lamports: 1_461_600,
                  owner: "11111111111111111111111111111111",
                  rent_epoch: 18_446_744_073_709_551_615,
                  space: 5
                }}
    end

    test "returns nil for nonexistent account" do
      assert RPC.get_account_info(@nonexistent_pubkey) == {:ok, nil}
    end
  end

  describe "get_multiple_accounts/2" do
    test "returns list with account info and nils" do
      assert {:ok, [account, nil]} =
               RPC.get_multiple_accounts([@test_pubkey, @nonexistent_pubkey])

      assert account == %{
               data: ["", "base64"],
               executable: false,
               lamports: 500_000,
               owner: "11111111111111111111111111111111",
               rent_epoch: 0,
               space: 0
             }
    end
  end

  # ---------------------------------------------------------------------------
  # Blockhash / slot methods
  # ---------------------------------------------------------------------------

  describe "get_latest_blockhash/1" do
    test "returns decoded blockhash and last valid block height" do
      assert RPC.get_latest_blockhash() ==
               {:ok,
                %{
                  blockhash: @mock_blockhash,
                  last_valid_block_height: 256_200
                }}
    end

    test "blockhash is 32 raw bytes, not a Base58 string" do
      {:ok, %{blockhash: bh}} = RPC.get_latest_blockhash()
      assert byte_size(bh) == 32
      # Verify roundtrip: encode back to Base58 matches the mock
      assert Signet.Base58.encode(bh) == "4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn"
    end
  end

  describe "get_slot/1" do
    test "returns slot number" do
      assert RPC.get_slot() == {:ok, 256_000}
    end
  end

  describe "get_block_height/1" do
    test "returns block height" do
      assert RPC.get_block_height() == {:ok, 255_980}
    end
  end

  # ---------------------------------------------------------------------------
  # Transaction methods
  # ---------------------------------------------------------------------------

  describe "get_transaction/2" do
    test "returns full transaction data" do
      assert {:ok, trx} = RPC.get_transaction("some_signature")

      assert trx["blockTime"] == 1_708_300_522
      assert trx["slot"] == 255_900
      assert trx["version"] == "legacy"

      assert trx["meta"] == %{
               "err" => nil,
               "fee" => 5000,
               "preBalances" => [10_000_000_000, 0, 1],
               "postBalances" => [8_999_995_000, 1_000_000_000, 1],
               "logMessages" => [
                 "Program 11111111111111111111111111111111 invoke [1]",
                 "Program 11111111111111111111111111111111 success"
               ],
               "innerInstructions" => [],
               "rewards" => nil,
               "loadedAddresses" => %{"readonly" => [], "writable" => []},
               "computeUnitsConsumed" => 150
             }
    end

    test "returns nil for not-found transaction" do
      assert RPC.get_transaction("not_found_sig") == {:ok, nil}
    end
  end

  describe "get_signature_statuses/2" do
    test "finalized status" do
      assert RPC.get_signature_statuses(["finalized_sig"]) ==
               {:ok,
                [
                  %{
                    slot: 255_900,
                    confirmations: nil,
                    err: nil,
                    confirmation_status: :finalized
                  }
                ]}
    end

    test "confirmed status with confirmation count" do
      assert RPC.get_signature_statuses(["confirmed_sig"]) ==
               {:ok,
                [
                  %{
                    slot: 255_900,
                    confirmations: 10,
                    err: nil,
                    confirmation_status: :confirmed
                  }
                ]}
    end

    test "failed transaction" do
      assert RPC.get_signature_statuses(["failed_sig"]) ==
               {:ok,
                [
                  %{
                    slot: 255_900,
                    confirmations: nil,
                    err: %{"InstructionError" => [0, "InsufficientFunds"]},
                    confirmation_status: :finalized
                  }
                ]}
    end

    test "unknown signature returns nil" do
      assert RPC.get_signature_statuses(["unknown_sig"]) == {:ok, [nil]}
    end

    test "mixed statuses" do
      assert {:ok, [finalized, nil, failed]} =
               RPC.get_signature_statuses(["finalized_sig", "unknown_sig", "failed_sig"])

      assert finalized.confirmation_status == :finalized
      assert finalized.err == nil
      assert nil == nil
      assert failed.err == %{"InstructionError" => [0, "InsufficientFunds"]}
    end
  end

  # ---------------------------------------------------------------------------
  # Rent / fees
  # ---------------------------------------------------------------------------

  describe "get_minimum_balance_for_rent_exemption/2" do
    test "returns lamports for token account size" do
      assert RPC.get_minimum_balance_for_rent_exemption(165) == {:ok, 2_039_280}
    end

    test "returns lamports for zero-data account" do
      assert RPC.get_minimum_balance_for_rent_exemption(0) == {:ok, 890_880}
    end
  end

  # ---------------------------------------------------------------------------
  # Token methods
  # ---------------------------------------------------------------------------

  describe "get_token_account_balance/2" do
    test "returns parsed token amount" do
      assert RPC.get_token_account_balance(@test_pubkey) ==
               {:ok,
                %{
                  amount: 1_000_000_000,
                  decimals: 9,
                  ui_amount_string: "1"
                }}
    end
  end

  describe "get_token_accounts_by_owner/3" do
    test "filter by mint returns token accounts" do
      assert {:ok, [account]} =
               RPC.get_token_accounts_by_owner(@test_pubkey, mint: @test_pubkey)

      assert account.pubkey == "AyVfCw5fBuVTkzG4bBPiDfCkuS1YGrh2i6pRgLHMwmZr"
      assert account.account.lamports == 2_039_280
      assert account.account.space == 165
    end

    test "filter by program_id returns token accounts" do
      token_program = Signet.Solana.Programs.token_program()

      assert {:ok, accounts} =
               RPC.get_token_accounts_by_owner(@test_pubkey, program_id: token_program)

      assert length(accounts) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Fee methods
  # ---------------------------------------------------------------------------

  describe "get_recent_prioritization_fees/2" do
    test "returns fee list" do
      assert RPC.get_recent_prioritization_fees() ==
               {:ok,
                [
                  %{slot: 255_998, prioritization_fee: 0},
                  %{slot: 255_999, prioritization_fee: 1000},
                  %{slot: 256_000, prioritization_fee: 500}
                ]}
    end
  end

  # ---------------------------------------------------------------------------
  # Node info
  # ---------------------------------------------------------------------------

  describe "get_health/1" do
    test "returns :ok when healthy" do
      assert RPC.get_health() == :ok
    end
  end

  describe "get_version/1" do
    test "returns parsed version info" do
      assert RPC.get_version() ==
               {:ok, %{solana_core: "1.18.26", feature_set: 2_891_131_721}}
    end
  end

  # ---------------------------------------------------------------------------
  # Write methods
  # ---------------------------------------------------------------------------

  describe "send_transaction/2" do
    test "sends transaction struct and returns signature" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.transfer(fee_payer, recipient, 1_000_000)
      msg = Signet.Solana.Transaction.build_message(fee_payer, [ix], blockhash)
      {_pub, seed} = Signet.Solana.Keys.from_seed(<<1::256>>)
      trx = Signet.Solana.Transaction.sign(msg, [seed])

      assert RPC.send_transaction(trx) ==
               {:ok,
                "4Lz3raap9pEVGjT4EuVmNxTzMEj3EhVFKBonVFcnjiMwFKwEqh9TuPRYSv3TpK6ia4W33kMtJMdRJiL"}
    end

    test "sends raw bytes" do
      assert RPC.send_transaction(<<1, 2, 3>>) ==
               {:ok,
                "4Lz3raap9pEVGjT4EuVmNxTzMEj3EhVFKBonVFcnjiMwFKwEqh9TuPRYSv3TpK6ia4W33kMtJMdRJiL"}
    end
  end

  describe "simulate_transaction/2" do
    test "returns simulation result" do
      assert RPC.simulate_transaction(<<1, 2, 3>>) ==
               {:ok,
                %{
                  err: nil,
                  logs: [
                    "Program 11111111111111111111111111111111 invoke [1]",
                    "Program 11111111111111111111111111111111 success"
                  ],
                  units_consumed: 150
                }}
    end

    test "accepts transaction struct" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>
      ix = Signet.Solana.SystemProgram.transfer(fee_payer, recipient, 100)
      msg = Signet.Solana.Transaction.build_message(fee_payer, [ix], blockhash)
      {_pub, seed} = Signet.Solana.Keys.from_seed(<<1::256>>)
      trx = Signet.Solana.Transaction.sign(msg, [seed])

      assert {:ok, %{err: nil, logs: [_ | _]}} = RPC.simulate_transaction(trx)
    end
  end

  describe "request_airdrop/3" do
    test "returns airdrop transaction signature" do
      assert RPC.request_airdrop(@test_pubkey, 1_000_000_000) ==
               {:ok, "2ZE3FQsWzjbkyNKP5qEDGjJEsaWmVFBCKSBMxpZUTgBs1PWDM1jN6hUEyFz1"}
    end
  end
end

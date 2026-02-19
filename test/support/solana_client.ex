defmodule Signet.Solana.Test.Client do
  @moduledoc """
  Mock Solana JSON-RPC client for testing.

  Uses address-based dispatch to return different responses:
  - Standard addresses return normal responses
  - Specific "magic" addresses trigger error cases or edge cases
  """

  # Known test addresses (Base58-encoded)
  # All-zeros seed → "4zvwRjXUKGfvwnParsHAS3HuSVzV5cA4McphgmoCtajS"
  @nonexistent_account "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
  @error_account "11111111111111111111111111111112"

  def request(%Finch.Request{body: body}, _finch_name, _opts) do
    %{"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => id} =
      Jason.decode!(body)

    result = dispatch(method, params)

    return_body =
      case result do
        {:rpc_error, error} ->
          Jason.encode!(%{"jsonrpc" => "2.0", "error" => error, "id" => id})

        _ ->
          Jason.encode!(%{"jsonrpc" => "2.0", "result" => result, "id" => id})
      end

    {:ok, %Finch.Response{status: 200, body: return_body}}
  end

  # ---------------------------------------------------------------------------
  # getBalance
  # ---------------------------------------------------------------------------

  defp dispatch("getBalance", [@error_account | _]) do
    {:rpc_error, %{"code" => -32600, "message" => "Invalid request"}}
  end

  defp dispatch("getBalance", [_pubkey | _]) do
    %{"context" => %{"slot" => 256_000}, "value" => 1_500_000_000}
  end

  # ---------------------------------------------------------------------------
  # getAccountInfo
  # ---------------------------------------------------------------------------

  defp dispatch("getAccountInfo", [@nonexistent_account, _config]) do
    %{"context" => %{"slot" => 256_000}, "value" => nil}
  end

  defp dispatch("getAccountInfo", [_pubkey, %{"encoding" => "base64"}]) do
    %{
      "context" => %{"slot" => 256_000},
      "value" => %{
        "data" => ["AQAAAAA=", "base64"],
        "executable" => false,
        "lamports" => 1_461_600,
        "owner" => "11111111111111111111111111111111",
        "rentEpoch" => 18_446_744_073_709_551_615,
        "space" => 5
      }
    }
  end

  defp dispatch("getAccountInfo", [_pubkey, _config]) do
    %{
      "context" => %{"slot" => 256_000},
      "value" => %{
        "data" => ["AQAAAAA=", "base64"],
        "executable" => false,
        "lamports" => 1_461_600,
        "owner" => "11111111111111111111111111111111",
        "rentEpoch" => 18_446_744_073_709_551_615,
        "space" => 5
      }
    }
  end

  # ---------------------------------------------------------------------------
  # getMultipleAccounts
  # ---------------------------------------------------------------------------

  defp dispatch("getMultipleAccounts", [pubkeys, _config]) do
    values =
      Enum.map(pubkeys, fn
        @nonexistent_account ->
          nil

        _ ->
          %{
            "data" => ["", "base64"],
            "executable" => false,
            "lamports" => 500_000,
            "owner" => "11111111111111111111111111111111",
            "rentEpoch" => 0,
            "space" => 0
          }
      end)

    %{"context" => %{"slot" => 256_000}, "value" => values}
  end

  # ---------------------------------------------------------------------------
  # getLatestBlockhash
  # ---------------------------------------------------------------------------

  defp dispatch("getLatestBlockhash", _) do
    %{
      "context" => %{"slot" => 256_000},
      "value" => %{
        "blockhash" => "4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn",
        "lastValidBlockHeight" => 256_200
      }
    }
  end

  # ---------------------------------------------------------------------------
  # getSlot / getBlockHeight
  # ---------------------------------------------------------------------------

  defp dispatch("getSlot", _), do: 256_000
  defp dispatch("getBlockHeight", _), do: 255_980

  # ---------------------------------------------------------------------------
  # getTransaction
  # ---------------------------------------------------------------------------

  defp dispatch("getTransaction", ["not_found_sig" | _]) do
    nil
  end

  defp dispatch("getTransaction", [_sig | _]) do
    %{
      "blockTime" => 1_708_300_522,
      "slot" => 255_900,
      "version" => "legacy",
      "meta" => %{
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
      },
      "transaction" => %{
        "signatures" => [
          "4Lz3raap9pEVGjT4EuVmNxTzMEj3EhVFKBonVFcnjiMwFKwEqh9TuPRYSv3TpK6ia4W33kMtJMdRJiL"
        ],
        "message" => %{
          "accountKeys" => [
            "4zvwRjXUKGfvwnParsHAS3HuSVzV5cA4McphgmoCtajS",
            "FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z",
            "11111111111111111111111111111111"
          ],
          "header" => %{
            "numRequiredSignatures" => 1,
            "numReadonlySignedAccounts" => 0,
            "numReadonlyUnsignedAccounts" => 1
          },
          "instructions" => [
            %{
              "programIdIndex" => 2,
              "accounts" => [0, 1],
              "data" => "3Bxs4h24hBtQy9rw"
            }
          ],
          "recentBlockhash" => "4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn"
        }
      }
    }
  end

  # ---------------------------------------------------------------------------
  # getSignatureStatuses
  # ---------------------------------------------------------------------------

  defp dispatch("getSignatureStatuses", [sigs | _]) do
    values =
      Enum.map(sigs, fn
        "confirmed_sig" ->
          %{
            "slot" => 255_900,
            "confirmations" => 10,
            "err" => nil,
            "confirmationStatus" => "confirmed"
          }

        "failed_sig" ->
          %{
            "slot" => 255_900,
            "confirmations" => nil,
            "err" => %{"InstructionError" => [0, "InsufficientFunds"]},
            "confirmationStatus" => "finalized"
          }

        "unknown_sig" ->
          nil

        _ ->
          %{
            "slot" => 255_900,
            "confirmations" => nil,
            "err" => nil,
            "confirmationStatus" => "finalized"
          }
      end)

    %{"context" => %{"slot" => 256_000}, "value" => values}
  end

  # ---------------------------------------------------------------------------
  # getMinimumBalanceForRentExemption
  # ---------------------------------------------------------------------------

  defp dispatch("getMinimumBalanceForRentExemption", [165 | _]), do: 2_039_280
  defp dispatch("getMinimumBalanceForRentExemption", [0 | _]), do: 890_880
  defp dispatch("getMinimumBalanceForRentExemption", _), do: 890_880

  # ---------------------------------------------------------------------------
  # getTokenAccountBalance
  # ---------------------------------------------------------------------------

  defp dispatch("getTokenAccountBalance", [_pubkey | _]) do
    %{
      "context" => %{"slot" => 256_000},
      "value" => %{
        "amount" => "1000000000",
        "decimals" => 9,
        "uiAmount" => 1.0,
        "uiAmountString" => "1"
      }
    }
  end

  # ---------------------------------------------------------------------------
  # getTokenAccountsByOwner
  # ---------------------------------------------------------------------------

  # Filter by mint - returns matching token accounts
  defp dispatch("getTokenAccountsByOwner", [_owner, %{"mint" => _mint}, _config]) do
    %{
      "context" => %{"slot" => 256_000},
      "value" => [
        %{
          "pubkey" => "AyVfCw5fBuVTkzG4bBPiDfCkuS1YGrh2i6pRgLHMwmZr",
          "account" => %{
            "data" => %{
              "parsed" => %{
                "info" => %{
                  "isNative" => false,
                  "mint" => "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                  "owner" => "4zvwRjXUKGfvwnParsHAS3HuSVzV5cA4McphgmoCtajS",
                  "state" => "initialized",
                  "tokenAmount" => %{
                    "amount" => "1500000000",
                    "decimals" => 6,
                    "uiAmount" => 1500.0,
                    "uiAmountString" => "1500"
                  }
                },
                "type" => "account"
              },
              "program" => "spl-token",
              "space" => 165
            },
            "executable" => false,
            "lamports" => 2_039_280,
            "owner" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            "rentEpoch" => 18_446_744_073_709_551_615,
            "space" => 165
          }
        }
      ]
    }
  end

  # Filter by programId - returns all token accounts
  defp dispatch("getTokenAccountsByOwner", [_owner, %{"programId" => program_id}, _config]) do
    accounts =
      case program_id do
        "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" ->
          [
            token_account_fixture(
              "AyVfCw5fBuVTkzG4bBPiDfCkuS1YGrh2i6pRgLHMwmZr",
              "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
              "1500000000",
              6
            ),
            token_account_fixture(
              "BzVfCw5fBuVTkzG4bBPiDfCkuS1YGrh2i6pRgLHMwmZs",
              "So11111111111111111111111111111111111111112",
              "5000000000",
              9
            )
          ]

        "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb" ->
          [
            token_account_fixture(
              "CzVfCw5fBuVTkzG4bBPiDfCkuS1YGrh2i6pRgLHMwmZt",
              "2DEy3MN8J2zKWVoYTPKg4wifoDBavX6XpSgbRsfuLAMn",
              "999000000000",
              9
            )
          ]

        _ ->
          []
      end

    %{"context" => %{"slot" => 256_000}, "value" => accounts}
  end

  # ---------------------------------------------------------------------------
  # getRecentPrioritizationFees
  # ---------------------------------------------------------------------------

  defp dispatch("getRecentPrioritizationFees", _) do
    [
      %{"slot" => 255_998, "prioritizationFee" => 0},
      %{"slot" => 255_999, "prioritizationFee" => 1000},
      %{"slot" => 256_000, "prioritizationFee" => 500}
    ]
  end

  # ---------------------------------------------------------------------------
  # getHealth / getVersion
  # ---------------------------------------------------------------------------

  defp dispatch("getHealth", _), do: "ok"

  defp dispatch("getVersion", _) do
    %{"solana-core" => "1.18.26", "feature-set" => 2_891_131_721}
  end

  # ---------------------------------------------------------------------------
  # sendTransaction
  # ---------------------------------------------------------------------------

  defp dispatch("sendTransaction", [_encoded, _config]) do
    "4Lz3raap9pEVGjT4EuVmNxTzMEj3EhVFKBonVFcnjiMwFKwEqh9TuPRYSv3TpK6ia4W33kMtJMdRJiL"
  end

  # ---------------------------------------------------------------------------
  # simulateTransaction
  # ---------------------------------------------------------------------------

  defp dispatch("simulateTransaction", [_encoded, _config]) do
    %{
      "context" => %{"slot" => 256_000},
      "value" => %{
        "err" => nil,
        "logs" => [
          "Program 11111111111111111111111111111111 invoke [1]",
          "Program 11111111111111111111111111111111 success"
        ],
        "unitsConsumed" => 150
      }
    }
  end

  # ---------------------------------------------------------------------------
  # requestAirdrop
  # ---------------------------------------------------------------------------

  defp dispatch("requestAirdrop", [_pubkey, _lamports | _]) do
    "2ZE3FQsWzjbkyNKP5qEDGjJEsaWmVFBCKSBMxpZUTgBs1PWDM1jN6hUEyFz1"
  end

  # ---------------------------------------------------------------------------
  # Fallback
  # ---------------------------------------------------------------------------

  defp dispatch(method, _params) do
    {:rpc_error, %{"code" => -32601, "message" => "Method not found: #{method}"}}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp token_account_fixture(pubkey, mint, amount, decimals) do
    %{
      "pubkey" => pubkey,
      "account" => %{
        "data" => %{
          "parsed" => %{
            "info" => %{
              "isNative" => false,
              "mint" => mint,
              "owner" => "4zvwRjXUKGfvwnParsHAS3HuSVzV5cA4McphgmoCtajS",
              "state" => "initialized",
              "tokenAmount" => %{
                "amount" => amount,
                "decimals" => decimals,
                "uiAmount" => String.to_integer(amount) / :math.pow(10, decimals),
                "uiAmountString" => "#{String.to_integer(amount) / :math.pow(10, decimals)}"
              }
            },
            "type" => "account"
          },
          "program" => "spl-token",
          "space" => 165
        },
        "executable" => false,
        "lamports" => 2_039_280,
        "owner" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
        "rentEpoch" => 18_446_744_073_709_551_615,
        "space" => 165
      }
    }
  end
end

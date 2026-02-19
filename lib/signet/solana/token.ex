defmodule Signet.Solana.Token do
  @moduledoc """
  High-level token operations for Solana: balance queries, transfers,
  and ATA management.

  Combines RPC calls with PDA derivation and instruction building.
  Analogous to `Signet.Erc20` on the Ethereum side.

  ## Examples

      # Get USDC balance for a wallet
      {:ok, balance} = Signet.Solana.Token.get_balance(wallet, usdc_mint)

      # Get all token balances
      {:ok, balances} = Signet.Solana.Token.get_all_balances(wallet)

      # Build transfer instructions (includes ATA creation if needed)
      instructions = Signet.Solana.Token.transfer_instructions(
        from_wallet, to_wallet, mint, 1_000_000, 6
      )
  """

  alias Signet.Solana.{RPC, ATA, TokenProgram, Programs}

  @doc """
  Get the balance of a specific token for a wallet.

  Uses `getTokenAccountsByOwner` with a mint filter and `jsonParsed` encoding.
  Sums across all token accounts for the mint (usually just the ATA, but
  handles edge cases with multiple accounts).

  Returns the raw integer amount, decimals, and mint address.
  """
  @spec get_balance(<<_::256>>, <<_::256>>, keyword()) ::
          {:ok,
           %{
             amount: non_neg_integer(),
             decimals: non_neg_integer(),
             mint: String.t()
           }}
          | {:error, term()}
  def get_balance(wallet, mint, opts \\ []) do
    mint_b58 = Signet.Base58.encode(mint)

    with {:ok, accounts} <-
           RPC.get_token_accounts_by_owner(wallet, [mint: mint], opts) do
      case accounts do
        [] ->
          {:ok, %{amount: 0, decimals: 0, mint: mint_b58}}

        accounts ->
          {total, decimals} =
            Enum.reduce(accounts, {0, 0}, fn acct, {sum, _dec} ->
              info = get_in(acct, [:account, :data, "parsed", "info"])
              token_amount = info["tokenAmount"]
              amount = String.to_integer(token_amount["amount"])
              {sum + amount, token_amount["decimals"]}
            end)

          {:ok, %{amount: total, decimals: decimals, mint: mint_b58}}
      end
    end
  end

  @doc """
  Get all token balances for a wallet.

  Queries both SPL Token Program and Token-2022 by default.

  ## Options
  - `:include_token_2022` - also query Token-2022 (default: true)
  """
  @spec get_all_balances(<<_::256>>, keyword()) ::
          {:ok,
           [
             %{
               mint: String.t(),
               amount: non_neg_integer(),
               decimals: non_neg_integer(),
               token_account: String.t()
             }
           ]}
          | {:error, term()}
  def get_all_balances(wallet, opts \\ []) do
    include_2022 = Keyword.get(opts, :include_token_2022, true)

    with {:ok, token_accounts} <-
           RPC.get_token_accounts_by_owner(
             wallet,
             [program_id: Programs.token_program()],
             opts
           ) do
      balances = parse_token_accounts(token_accounts)

      if include_2022 do
        with {:ok, t22_accounts} <-
               RPC.get_token_accounts_by_owner(
                 wallet,
                 [program_id: Programs.token_2022_program()],
                 opts
               ) do
          {:ok, balances ++ parse_token_accounts(t22_accounts)}
        end
      else
        {:ok, balances}
      end
    end
  end

  @doc """
  Build instructions for a token transfer between wallets.

  Handles ATA derivation for both source and destination. Includes an
  idempotent ATA creation for the destination (no-op if it already exists).
  Uses `transfer_checked` for safety.

  Returns a list of instructions suitable for `Transaction.build_message/3`.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec transfer_instructions(
          <<_::256>>,
          <<_::256>>,
          <<_::256>>,
          non_neg_integer(),
          non_neg_integer(),
          keyword()
        ) :: [Signet.Solana.Transaction.Instruction.t()]
  def transfer_instructions(from_wallet, to_wallet, mint, amount, decimals, opts \\ []) do
    {from_ata, _} = ATA.find_address(from_wallet, mint, opts)
    {to_ata, _} = ATA.find_address(to_wallet, mint, opts)

    create_ix = ATA.create_idempotent(from_wallet, to_wallet, mint, opts)

    transfer_ix =
      TokenProgram.transfer_checked(from_ata, mint, to_ata, from_wallet, amount, decimals, opts)

    [create_ix, transfer_ix]
  end

  defp parse_token_accounts(accounts) do
    Enum.map(accounts, fn acct ->
      info = get_in(acct, [:account, :data, "parsed", "info"])
      token_amount = info["tokenAmount"]

      %{
        mint: info["mint"],
        amount: String.to_integer(token_amount["amount"]),
        decimals: token_amount["decimals"],
        token_account: acct.pubkey
      }
    end)
  end
end

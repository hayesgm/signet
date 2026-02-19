defmodule Signet.Solana.Programs do
  @moduledoc """
  Well-known Solana program IDs and addresses.

  Centralizes program addresses to avoid scattered Base58 decoding
  across modules.
  """

  use Signet.Base58

  @doc "System Program (`11111111111111111111111111111111`)"
  def system_program, do: <<0::256>>

  @doc "SPL Token Program (`TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`)"
  def token_program, do: ~B58[TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA]

  @doc "Token-2022 Program (`TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb`)"
  def token_2022_program, do: ~B58[TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb]

  @doc "Associated Token Account Program (`ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL`)"
  def ata_program, do: ~B58[ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL]

  @doc "Compute Budget Program (`ComputeBudget111111111111111111111111111111`)"
  def compute_budget_program, do: ~B58[ComputeBudget111111111111111111111111111111]

  @doc "Wrapped SOL Mint (`So11111111111111111111111111111111111111112`)"
  def wrapped_sol_mint, do: ~B58[So11111111111111111111111111111111111111112]
end

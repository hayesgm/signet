defmodule Signet.Solana.ATA do
  @moduledoc """
  Associated Token Account (ATA) utilities for Solana.

  An ATA is the canonical token account for a (wallet, mint) pair. It is
  a PDA derived with seeds `[wallet, token_program_id, mint]` under the
  Associated Token Account Program.

  ## Examples

      iex> {pub, _} = Signet.Solana.Keys.from_seed(<<1::256>>)
      iex> mint = Signet.Solana.Programs.wrapped_sol_mint()
      iex> {ata, bump} = Signet.Solana.ATA.find_address(pub, mint)
      iex> byte_size(ata) == 32 and bump >= 0 and bump <= 255
      true
  """

  alias Signet.Solana.{PDA, Programs}
  alias Signet.Solana.Transaction.{Instruction, AccountMeta}

  @doc """
  Derive the associated token account address for a wallet + mint.

  Pure computation (no RPC call). Returns `{ata_address, bump_seed}`.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
    Pass `Programs.token_2022_program()` for Token-2022 mints.
  """
  @spec find_address(<<_::256>>, <<_::256>>, keyword()) :: {<<_::256>>, non_neg_integer()}
  def find_address(<<wallet::binary-32>>, <<mint::binary-32>>, opts \\ []) do
    token_program = Keyword.get(opts, :token_program, Programs.token_program())

    PDA.find_program_address!(
      [wallet, token_program, mint],
      Programs.ata_program()
    )
  end

  @doc """
  Build an instruction to create an ATA. Fails if it already exists.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec create(<<_::256>>, <<_::256>>, <<_::256>>, keyword()) :: Instruction.t()
  def create(<<payer::binary-32>>, <<wallet::binary-32>>, <<mint::binary-32>>, opts \\ []) do
    build_create_instruction(payer, wallet, mint, <<0>>, opts)
  end

  @doc """
  Build an instruction to create an ATA, succeeding even if it already exists.

  This is the preferred variant for most use cases - it is a no-op if the
  ATA already exists.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec create_idempotent(<<_::256>>, <<_::256>>, <<_::256>>, keyword()) :: Instruction.t()
  def create_idempotent(
        <<payer::binary-32>>,
        <<wallet::binary-32>>,
        <<mint::binary-32>>,
        opts \\ []
      ) do
    build_create_instruction(payer, wallet, mint, <<1>>, opts)
  end

  # data is the ATA program instruction index:
  #   <<0>> = Create (fails if ATA already exists)
  #   <<1>> = CreateIdempotent (no-op if ATA already exists)
  defp build_create_instruction(payer, wallet, mint, data, opts) do
    token_program = Keyword.get(opts, :token_program, Programs.token_program())
    {ata, _bump} = find_address(wallet, mint, opts)

    %Instruction{
      program_id: Programs.ata_program(),
      accounts: [
        %AccountMeta{pubkey: payer, is_signer: true, is_writable: true},
        %AccountMeta{pubkey: ata, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: wallet, is_signer: false, is_writable: false},
        %AccountMeta{pubkey: mint, is_signer: false, is_writable: false},
        %AccountMeta{pubkey: Programs.system_program(), is_signer: false, is_writable: false},
        %AccountMeta{pubkey: token_program, is_signer: false, is_writable: false}
      ],
      data: data
    }
  end
end

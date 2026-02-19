defmodule Signet.Solana.TokenProgram do
  @moduledoc """
  Instruction builders for the SPL Token Program.

  Works with both SPL Token and Token-2022 via the `:token_program` option.
  SPL Token uses a 1-byte instruction index (unlike System Program's 4-byte u32).

  ## Examples

      iex> ix = Signet.Solana.TokenProgram.transfer(<<1::256>>, <<2::256>>, <<3::256>>, 1_000_000)
      iex> ix.data
      <<3, 64, 66, 15, 0, 0, 0, 0, 0>>
  """

  alias Signet.Solana.Transaction.{Instruction, AccountMeta}
  alias Signet.Solana.Programs

  @doc """
  Transfer tokens from source to destination.

  The authority must sign the transaction.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec transfer(<<_::256>>, <<_::256>>, <<_::256>>, non_neg_integer(), keyword()) ::
          Instruction.t()
  def transfer(
        <<source::binary-32>>,
        <<destination::binary-32>>,
        <<authority::binary-32>>,
        amount,
        opts \\ []
      )
      when is_integer(amount) and amount >= 0 do
    %Instruction{
      program_id: token_program(opts),
      accounts: [
        %AccountMeta{pubkey: source, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: destination, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: authority, is_signer: true, is_writable: false}
      ],
      data: <<3, amount::little-unsigned-64>>
    }
  end

  @doc """
  Transfer tokens with decimal verification (preferred over `transfer/5`).

  Requires passing the mint, preventing accidental wrong-decimal transfers.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec transfer_checked(
          <<_::256>>,
          <<_::256>>,
          <<_::256>>,
          <<_::256>>,
          non_neg_integer(),
          non_neg_integer(),
          keyword()
        ) :: Instruction.t()
  def transfer_checked(
        <<source::binary-32>>,
        <<mint::binary-32>>,
        <<destination::binary-32>>,
        <<authority::binary-32>>,
        amount,
        decimals,
        opts \\ []
      )
      when is_integer(amount) and amount >= 0 and is_integer(decimals) and decimals >= 0 do
    %Instruction{
      program_id: token_program(opts),
      accounts: [
        %AccountMeta{pubkey: source, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: mint, is_signer: false, is_writable: false},
        %AccountMeta{pubkey: destination, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: authority, is_signer: true, is_writable: false}
      ],
      data: <<12, amount::little-unsigned-64, decimals::unsigned-8>>
    }
  end

  @doc """
  Approve a delegate to transfer up to `amount` tokens from source.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec approve(<<_::256>>, <<_::256>>, <<_::256>>, non_neg_integer(), keyword()) ::
          Instruction.t()
  def approve(
        <<source::binary-32>>,
        <<delegate::binary-32>>,
        <<authority::binary-32>>,
        amount,
        opts \\ []
      )
      when is_integer(amount) and amount >= 0 do
    %Instruction{
      program_id: token_program(opts),
      accounts: [
        %AccountMeta{pubkey: source, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: delegate, is_signer: false, is_writable: false},
        %AccountMeta{pubkey: authority, is_signer: true, is_writable: false}
      ],
      data: <<4, amount::little-unsigned-64>>
    }
  end

  @doc """
  Close a token account, transferring remaining SOL rent to destination.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec close_account(<<_::256>>, <<_::256>>, <<_::256>>, keyword()) :: Instruction.t()
  def close_account(
        <<account::binary-32>>,
        <<destination::binary-32>>,
        <<authority::binary-32>>,
        opts \\ []
      ) do
    %Instruction{
      program_id: token_program(opts),
      accounts: [
        %AccountMeta{pubkey: account, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: destination, is_signer: false, is_writable: true},
        %AccountMeta{pubkey: authority, is_signer: true, is_writable: false}
      ],
      data: <<9>>
    }
  end

  @doc """
  Sync the native SOL balance of a wrapped SOL token account.

  ## Options
  - `:token_program` - Override the token program (default: SPL Token Program).
  """
  @spec sync_native(<<_::256>>, keyword()) :: Instruction.t()
  def sync_native(<<account::binary-32>>, opts \\ []) do
    %Instruction{
      program_id: token_program(opts),
      accounts: [
        %AccountMeta{pubkey: account, is_signer: false, is_writable: true}
      ],
      data: <<17>>
    }
  end

  defp token_program(opts), do: Keyword.get(opts, :token_program, Programs.token_program())
end

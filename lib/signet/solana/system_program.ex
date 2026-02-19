defmodule Signet.Solana.SystemProgram do
  @moduledoc """
  Instructions for the Solana System Program.

  The System Program (address: `11111111111111111111111111111111`, 32 zero bytes)
  handles basic operations like SOL transfers and account creation.
  """

  alias Signet.Solana.Transaction.{Instruction, AccountMeta}
  alias Signet.Solana.Programs

  @doc """
  Returns the System Program pubkey (32 zero bytes).

  Delegates to `Signet.Solana.Programs.system_program/0`.
  """
  @spec program_id() :: <<_::256>>
  def program_id, do: Programs.system_program()

  @doc """
  Build a transfer instruction (SOL transfer).

  System Program instruction index 2.

  ## Examples

      iex> ix = Signet.Solana.SystemProgram.transfer(<<1::256>>, <<2::256>>, 1_000_000_000)
      iex> ix.program_id
      <<0::256>>
      iex> byte_size(ix.data)
      12
  """
  @spec transfer(<<_::256>>, <<_::256>>, non_neg_integer()) :: Instruction.t()
  def transfer(<<from::binary-32>>, <<to::binary-32>>, lamports)
      when is_integer(lamports) and lamports >= 0 do
    %Instruction{
      program_id: Programs.system_program(),
      accounts: [
        %AccountMeta{pubkey: from, is_signer: true, is_writable: true},
        %AccountMeta{pubkey: to, is_signer: false, is_writable: true}
      ],
      data: <<2::little-unsigned-32, lamports::little-unsigned-64>>
    }
  end

  @doc """
  Build a create_account instruction.

  System Program instruction index 0.

  ## Examples

      iex> ix = Signet.Solana.SystemProgram.create_account(<<1::256>>, <<2::256>>, 1_000_000, 165, <<3::256>>)
      iex> ix.program_id
      <<0::256>>
      iex> byte_size(ix.data)
      52
  """
  @spec create_account(<<_::256>>, <<_::256>>, non_neg_integer(), non_neg_integer(), <<_::256>>) ::
          Instruction.t()
  def create_account(
        <<from::binary-32>>,
        <<new_account::binary-32>>,
        lamports,
        space,
        <<owner::binary-32>>
      )
      when is_integer(lamports) and lamports >= 0 and is_integer(space) and space >= 0 do
    %Instruction{
      program_id: Programs.system_program(),
      accounts: [
        %AccountMeta{pubkey: from, is_signer: true, is_writable: true},
        %AccountMeta{pubkey: new_account, is_signer: true, is_writable: true}
      ],
      data:
        <<0::little-unsigned-32, lamports::little-unsigned-64, space::little-unsigned-64,
          owner::binary-32>>
    }
  end
end

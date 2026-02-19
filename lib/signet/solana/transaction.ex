defmodule Signet.Solana.Transaction do
  @moduledoc """
  Build, serialize, sign, and deserialize Solana transactions (legacy format).

  A Solana transaction consists of signatures and a message. The message
  contains a header, ordered account keys, a recent blockhash, and compiled
  instructions. Each signer signs the raw serialized message bytes.

  ## Example: Build and sign a SOL transfer

      fee_payer = <<...>>  # 32-byte pubkey
      recipient = <<...>>  # 32-byte pubkey
      blockhash = <<...>>  # 32 bytes from getLatestBlockhash

      instruction = Signet.Solana.SystemProgram.transfer(fee_payer, recipient, 1_000_000_000)

      message = Signet.Solana.Transaction.build_message(fee_payer, [instruction], blockhash)
      transaction = Signet.Solana.Transaction.sign(message, [fee_payer_seed])

      # Serialize for RPC submission
      bytes = Signet.Solana.Transaction.serialize(transaction)
  """

  defmodule AccountMeta do
    @moduledoc "Account reference with permission flags."
    @type t :: %__MODULE__{
            pubkey: <<_::256>>,
            is_signer: boolean(),
            is_writable: boolean()
          }
    defstruct [:pubkey, :is_signer, :is_writable]
  end

  defmodule Instruction do
    @moduledoc "A high-level instruction before compilation."
    @type t :: %__MODULE__{
            program_id: <<_::256>>,
            accounts: [AccountMeta.t()],
            data: binary()
          }
    defstruct [:program_id, :accounts, :data]
  end

  defmodule Header do
    @moduledoc "Message header with account permission counts."
    @type t :: %__MODULE__{
            num_required_signatures: non_neg_integer(),
            num_readonly_signed_accounts: non_neg_integer(),
            num_readonly_unsigned_accounts: non_neg_integer()
          }
    defstruct num_required_signatures: 0,
              num_readonly_signed_accounts: 0,
              num_readonly_unsigned_accounts: 0
  end

  defmodule CompiledInstruction do
    @moduledoc "An instruction compiled to account indices."
    @type t :: %__MODULE__{
            program_id_index: non_neg_integer(),
            accounts: [non_neg_integer()],
            data: binary()
          }
    defstruct [:program_id_index, :accounts, :data]
  end

  defmodule Message do
    @moduledoc "The transaction message that gets signed."
    @type t :: %__MODULE__{
            header: Header.t(),
            account_keys: [<<_::256>>],
            recent_blockhash: <<_::256>>,
            instructions: [CompiledInstruction.t()]
          }
    defstruct [:header, :account_keys, :recent_blockhash, :instructions]
  end

  @type t :: %__MODULE__{
          signatures: [<<_::512>>],
          message: Message.t()
        }
  defstruct [:signatures, :message]

  import Bitwise

  # ---------------------------------------------------------------------------
  # Compact-u16 encoding
  # ---------------------------------------------------------------------------

  @doc """
  Encode a non-negative integer as a compact-u16 (variable-length).

  ## Examples

      iex> Signet.Solana.Transaction.encode_compact_u16(0)
      <<0>>

      iex> Signet.Solana.Transaction.encode_compact_u16(127)
      <<127>>

      iex> Signet.Solana.Transaction.encode_compact_u16(128)
      <<128, 1>>

      iex> Signet.Solana.Transaction.encode_compact_u16(16384)
      <<128, 128, 1>>
  """
  @spec encode_compact_u16(non_neg_integer()) :: binary()
  def encode_compact_u16(value) when value >= 0 and value <= 0xFFFF do
    encode_compact_u16_acc(value, <<>>)
  end

  defp encode_compact_u16_acc(value, acc) when value < 0x80 do
    acc <> <<value>>
  end

  defp encode_compact_u16_acc(value, acc) do
    encode_compact_u16_acc(value >>> 7, acc <> <<(value &&& 0x7F) ||| 0x80>>)
  end

  @doc """
  Decode a compact-u16 from the beginning of a binary.

  Returns `{value, rest}`.

  ## Examples

      iex> Signet.Solana.Transaction.decode_compact_u16(<<0, 99>>)
      {0, <<99>>}

      iex> Signet.Solana.Transaction.decode_compact_u16(<<128, 1, 99>>)
      {128, <<99>>}
  """
  @spec decode_compact_u16(binary()) :: {non_neg_integer(), binary()}
  def decode_compact_u16(binary) do
    decode_compact_u16_acc(binary, 0, 0)
  end

  defp decode_compact_u16_acc(<<byte, rest::binary>>, acc, shift) when byte >= 0x80 do
    decode_compact_u16_acc(rest, acc ||| (byte &&& 0x7F) <<< shift, shift + 7)
  end

  defp decode_compact_u16_acc(<<byte, rest::binary>>, acc, shift) do
    {acc ||| byte <<< shift, rest}
  end

  # ---------------------------------------------------------------------------
  # Building messages
  # ---------------------------------------------------------------------------

  @doc """
  Build a compiled message from high-level instructions.

  Handles account deduplication, permission merging, ordering, and index
  compilation. The fee payer is always placed first as a writable signer.
  """
  @spec build_message(<<_::256>>, [Instruction.t()], <<_::256>>) :: Message.t()
  def build_message(<<fee_payer::binary-32>>, instructions, <<recent_blockhash::binary-32>>) do
    # 1. Collect all unique accounts with merged permissions
    account_map = collect_accounts(fee_payer, instructions)

    # 2. Sort into the four groups
    {writable_signers, readonly_signers, writable_nonsigners, readonly_nonsigners} =
      partition_accounts(account_map, fee_payer)

    # 3. Build the ordered account keys list
    ordered_keys =
      writable_signers ++ readonly_signers ++ writable_nonsigners ++ readonly_nonsigners

    # 4. Build index lookup map
    index_map =
      ordered_keys
      |> Enum.with_index()
      |> Map.new()

    # 5. Compile instructions
    compiled =
      Enum.map(instructions, fn ix ->
        %CompiledInstruction{
          program_id_index: Map.fetch!(index_map, ix.program_id),
          accounts: Enum.map(ix.accounts, fn am -> Map.fetch!(index_map, am.pubkey) end),
          data: ix.data
        }
      end)

    # 6. Build header
    header = %Header{
      num_required_signatures: length(writable_signers) + length(readonly_signers),
      num_readonly_signed_accounts: length(readonly_signers),
      num_readonly_unsigned_accounts: length(readonly_nonsigners)
    }

    %Message{
      header: header,
      account_keys: ordered_keys,
      recent_blockhash: recent_blockhash,
      instructions: compiled
    }
  end

  defp collect_accounts(fee_payer, instructions) do
    # Start with fee payer as writable + signer
    init = %{fee_payer => {true, true}}

    Enum.reduce(instructions, init, fn ix, acc ->
      # Program ID is a readonly non-signer
      acc = Map.update(acc, ix.program_id, {false, false}, fn {s, w} -> {s, w} end)

      Enum.reduce(ix.accounts, acc, fn am, acc2 ->
        Map.update(acc2, am.pubkey, {am.is_signer, am.is_writable}, fn {s, w} ->
          {s or am.is_signer, w or am.is_writable}
        end)
      end)
    end)
  end

  defp partition_accounts(account_map, fee_payer) do
    # Remove fee payer from the map; it's always first in writable_signers
    rest = Map.delete(account_map, fee_payer)

    {ws, rs, wn, rn} =
      Enum.reduce(rest, {[], [], [], []}, fn {pubkey, {is_signer, is_writable}},
                                              {ws, rs, wn, rn} ->
        case {is_signer, is_writable} do
          {true, true} -> {[pubkey | ws], rs, wn, rn}
          {true, false} -> {ws, [pubkey | rs], wn, rn}
          {false, true} -> {ws, rs, [pubkey | wn], rn}
          {false, false} -> {ws, rs, wn, [pubkey | rn]}
        end
      end)

    # Fee payer is always first writable signer
    {[fee_payer | Enum.sort(ws)], Enum.sort(rs), Enum.sort(wn), Enum.sort(rn)}
  end

  # ---------------------------------------------------------------------------
  # Serialization
  # ---------------------------------------------------------------------------

  @doc """
  Serialize a message to the bytes that get signed.
  """
  @spec serialize_message(Message.t()) :: binary()
  def serialize_message(%Message{} = msg) do
    header_bytes =
      <<msg.header.num_required_signatures, msg.header.num_readonly_signed_accounts,
        msg.header.num_readonly_unsigned_accounts>>

    account_keys_bytes =
      encode_compact_u16(length(msg.account_keys)) <>
        Enum.reduce(msg.account_keys, <<>>, fn <<key::binary-32>>, acc -> acc <> key end)

    instructions_bytes =
      encode_compact_u16(length(msg.instructions)) <>
        Enum.reduce(msg.instructions, <<>>, fn ix, acc ->
          acc <> serialize_compiled_instruction(ix)
        end)

    header_bytes <> account_keys_bytes <> msg.recent_blockhash <> instructions_bytes
  end

  defp serialize_compiled_instruction(%CompiledInstruction{} = ix) do
    <<ix.program_id_index>> <>
      encode_compact_u16(length(ix.accounts)) <>
      :binary.list_to_bin(ix.accounts) <>
      encode_compact_u16(byte_size(ix.data)) <>
      ix.data
  end

  @doc """
  Serialize a full transaction (signatures + message) for RPC submission.
  """
  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{signatures: sigs, message: msg}) do
    encode_compact_u16(length(sigs)) <>
      Enum.reduce(sigs, <<>>, fn <<sig::binary-64>>, acc -> acc <> sig end) <>
      serialize_message(msg)
  end

  # ---------------------------------------------------------------------------
  # Deserialization
  # ---------------------------------------------------------------------------

  @doc """
  Deserialize a legacy transaction from binary.
  """
  @spec deserialize(binary()) :: {:ok, t()} | {:error, term()}
  def deserialize(binary) do
    with {num_sigs, rest} <- decode_compact_u16(binary),
         {:ok, sigs, rest} <- read_signatures(rest, num_sigs, []),
         {:ok, msg, <<>>} <- deserialize_message(rest) do
      {:ok, %__MODULE__{signatures: sigs, message: msg}}
    else
      {:error, _} = err -> err
      _ -> {:error, :invalid_transaction}
    end
  end

  @doc """
  Deserialize a message from binary.
  """
  @spec deserialize_message(binary()) :: {:ok, Message.t(), binary()} | {:error, term()}
  def deserialize_message(
        <<num_required_signatures, num_readonly_signed, num_readonly_unsigned, rest::binary>>
      ) do
    header = %Header{
      num_required_signatures: num_required_signatures,
      num_readonly_signed_accounts: num_readonly_signed,
      num_readonly_unsigned_accounts: num_readonly_unsigned
    }

    with {num_keys, rest} <- decode_compact_u16(rest),
         {:ok, keys, rest} <- read_pubkeys(rest, num_keys, []),
         <<recent_blockhash::binary-32, rest::binary>> <- rest,
         {num_ix, rest} <- decode_compact_u16(rest),
         {:ok, instructions, rest} <- read_instructions(rest, num_ix, []) do
      msg = %Message{
        header: header,
        account_keys: keys,
        recent_blockhash: recent_blockhash,
        instructions: instructions
      }

      {:ok, msg, rest}
    else
      _ -> {:error, :invalid_message}
    end
  end

  defp read_signatures(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp read_signatures(<<sig::binary-64, rest::binary>>, n, acc) when n > 0 do
    read_signatures(rest, n - 1, [sig | acc])
  end

  defp read_signatures(_, _, _), do: {:error, :insufficient_signature_data}

  defp read_pubkeys(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp read_pubkeys(<<key::binary-32, rest::binary>>, n, acc) when n > 0 do
    read_pubkeys(rest, n - 1, [key | acc])
  end

  defp read_pubkeys(_, _, _), do: {:error, :insufficient_pubkey_data}

  defp read_instructions(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp read_instructions(rest, n, acc) when n > 0 do
    <<program_id_index, rest::binary>> = rest
    {num_accounts, rest} = decode_compact_u16(rest)
    <<account_bytes::binary-size(num_accounts), rest::binary>> = rest
    accounts = :binary.bin_to_list(account_bytes)
    {data_len, rest} = decode_compact_u16(rest)
    <<data::binary-size(data_len), rest::binary>> = rest

    ix = %CompiledInstruction{
      program_id_index: program_id_index,
      accounts: accounts,
      data: data
    }

    read_instructions(rest, n - 1, [ix | acc])
  end

  # ---------------------------------------------------------------------------
  # Signing
  # ---------------------------------------------------------------------------

  @doc """
  Sign a message with one or more seeds and produce a full transaction.

  Seeds must be ordered to match the signer positions in the message's
  account keys (i.e., the first `num_required_signatures` accounts).
  """
  @spec sign(Message.t(), [<<_::256>>]) :: t()
  def sign(%Message{} = message, seeds) when is_list(seeds) do
    msg_bytes = serialize_message(message)

    signatures =
      Enum.map(seeds, fn <<seed::binary-32>> ->
        :crypto.sign(:eddsa, :none, msg_bytes, [seed, :ed25519])
      end)

    %__MODULE__{signatures: signatures, message: message}
  end

  @doc """
  Partially sign a message, filling only the specified signer positions.

  This is the core primitive for **sponsored transactions** (where one party
  pays fees on behalf of another). The typical flow is:

  1. User builds a message with the **sponsor's pubkey** as the fee payer
  2. User calls `sign_partial/2` with their own seed to sign their position
  3. User serializes the partially-signed transaction and sends it to the sponsor
  4. Sponsor deserializes and calls `add_signature/3` to fill in their position
  5. Sponsor submits the fully-signed transaction via `Signet.Solana.RPC.send_transaction/2`

  `signers` is a map of `%{account_index => seed}` where `account_index` is
  the position of the signer in the message's account keys list (0-based).
  Positions not present in the map get zero-filled placeholder signatures.

  ## Examples

      # User is account[1], sponsor is account[0] (fee payer)
      partial = Transaction.sign_partial(message, %{1 => user_seed})
      # => %Transaction{signatures: [<<0::512>>, <user_sig>], ...}

      # Serialize and send to sponsor
      bytes = Transaction.serialize(partial)
  """
  @spec sign_partial(Message.t(), %{non_neg_integer() => <<_::256>>}) :: t()
  def sign_partial(%Message{} = message, signers) when is_map(signers) do
    msg_bytes = serialize_message(message)
    num_signers = message.header.num_required_signatures

    signatures =
      Enum.map(0..(num_signers - 1), fn index ->
        case Map.get(signers, index) do
          nil -> <<0::512>>
          <<seed::binary-32>> -> :crypto.sign(:eddsa, :none, msg_bytes, [seed, :ed25519])
        end
      end)

    %__MODULE__{signatures: signatures, message: message}
  end

  @doc """
  Add a signature to a transaction at a specific signer position.

  Used to fill in a missing signature on a partially-signed transaction,
  typically by a sponsor or co-signer who receives the transaction from
  another party. See `sign_partial/2` for the full sponsored transaction flow.

  The `index` is the position in the signatures array (matching the account
  keys order in the message). The existing signature at that position is
  replaced.

  ## Examples

      # Sponsor receives a partially-signed transaction and adds their signature
      {:ok, partial} = Transaction.deserialize(bytes_from_user)
      msg_bytes = Transaction.serialize_message(partial.message)
      sponsor_sig = :crypto.sign(:eddsa, :none, msg_bytes, [sponsor_seed, :ed25519])
      full_trx = Transaction.add_signature(partial, 0, sponsor_sig)
  """
  @spec add_signature(t(), non_neg_integer(), <<_::512>>) :: t()
  def add_signature(%__MODULE__{} = transaction, index, <<signature::binary-64>>)
      when is_integer(index) and index >= 0 do
    signatures = List.replace_at(transaction.signatures, index, signature)
    %__MODULE__{transaction | signatures: signatures}
  end
end

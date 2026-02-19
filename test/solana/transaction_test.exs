defmodule Signet.Solana.TransactionTest do
  use ExUnit.Case, async: true
  doctest Signet.Solana.Transaction

  alias Signet.Solana.Transaction
  alias Signet.Solana.Transaction.{AccountMeta, Instruction}

  # ---------------------------------------------------------------------------
  # Compact-u16 encoding/decoding
  # ---------------------------------------------------------------------------

  describe "encode_compact_u16/1" do
    test "single-byte values (0-127)" do
      assert Transaction.encode_compact_u16(0) == <<0x00>>
      assert Transaction.encode_compact_u16(1) == <<0x01>>
      assert Transaction.encode_compact_u16(127) == <<0x7F>>
    end

    test "two-byte values (128-16383)" do
      assert Transaction.encode_compact_u16(128) == <<0x80, 0x01>>
      assert Transaction.encode_compact_u16(255) == <<0xFF, 0x01>>
      assert Transaction.encode_compact_u16(256) == <<0x80, 0x02>>
      assert Transaction.encode_compact_u16(16383) == <<0xFF, 0x7F>>
    end

    test "three-byte values (16384-65535)" do
      assert Transaction.encode_compact_u16(16384) == <<0x80, 0x80, 0x01>>
      assert Transaction.encode_compact_u16(65535) == <<0xFF, 0xFF, 0x03>>
    end
  end

  describe "decode_compact_u16/1" do
    test "roundtrip for all boundary values" do
      values = [0, 1, 127, 128, 255, 256, 16383, 16384, 65535]

      for v <- values do
        encoded = Transaction.encode_compact_u16(v)
        assert {^v, <<>>} = Transaction.decode_compact_u16(encoded)
      end
    end

    test "preserves trailing bytes" do
      assert {128, <<0xAB, 0xCD>>} = Transaction.decode_compact_u16(<<0x80, 0x01, 0xAB, 0xCD>>)
    end
  end

  # ---------------------------------------------------------------------------
  # build_message/3
  # ---------------------------------------------------------------------------

  describe "build_message/3" do
    # Deterministic test keys
    @fee_payer <<1::256>>
    @recipient <<2::256>>
    @authority <<3::256>>
    @program_a <<4::256>>
    @program_b <<5::256>>

    test "simple transfer: correct account ordering and header" do
      ix = %Instruction{
        program_id: <<0::256>>,
        accounts: [
          %AccountMeta{pubkey: @fee_payer, is_signer: true, is_writable: true},
          %AccountMeta{pubkey: @recipient, is_signer: false, is_writable: true}
        ],
        data: <<2::little-32, 1_000_000_000::little-64>>
      }

      msg = Transaction.build_message(@fee_payer, [ix], <<9::256>>)

      # Fee payer is first
      assert hd(msg.account_keys) == @fee_payer

      # Header: 1 signer, 0 readonly signed, 1 readonly unsigned (system program)
      assert msg.header.num_required_signatures == 1
      assert msg.header.num_readonly_signed_accounts == 0
      assert msg.header.num_readonly_unsigned_accounts == 1

      # 3 accounts total: fee_payer, recipient, system_program
      assert length(msg.account_keys) == 3

      # System program is last (readonly non-signer)
      assert List.last(msg.account_keys) == <<0::256>>

      # Blockhash preserved
      assert msg.recent_blockhash == <<9::256>>
    end

    test "deduplicates accounts and merges permissions" do
      # Same account referenced as non-signer in one ix, signer in another
      ix1 = %Instruction{
        program_id: @program_a,
        accounts: [
          %AccountMeta{pubkey: @authority, is_signer: false, is_writable: false}
        ],
        data: <<>>
      }

      ix2 = %Instruction{
        program_id: @program_a,
        accounts: [
          %AccountMeta{pubkey: @authority, is_signer: true, is_writable: true}
        ],
        data: <<>>
      }

      msg = Transaction.build_message(@fee_payer, [ix1, ix2], <<9::256>>)

      # authority should be promoted to writable signer
      # fee_payer = writable signer, authority = writable signer, program_a = readonly non-signer
      assert msg.header.num_required_signatures == 2
      assert msg.header.num_readonly_signed_accounts == 0
      assert msg.header.num_readonly_unsigned_accounts == 1

      # authority should be in the signers section (first 2 accounts)
      signer_keys = Enum.take(msg.account_keys, 2)
      assert @authority in signer_keys
    end

    test "fee payer is always first even if not in instructions" do
      ix = %Instruction{
        program_id: @program_a,
        accounts: [
          %AccountMeta{pubkey: @recipient, is_signer: false, is_writable: true}
        ],
        data: <<>>
      }

      msg = Transaction.build_message(@fee_payer, [ix], <<9::256>>)

      assert hd(msg.account_keys) == @fee_payer
      assert msg.header.num_required_signatures == 1
    end

    test "readonly signers are separated from writable signers" do
      ix = %Instruction{
        program_id: @program_a,
        accounts: [
          %AccountMeta{pubkey: @authority, is_signer: true, is_writable: false}
        ],
        data: <<>>
      }

      msg = Transaction.build_message(@fee_payer, [ix], <<9::256>>)

      # 2 signers total: fee_payer (writable), authority (readonly)
      assert msg.header.num_required_signatures == 2
      assert msg.header.num_readonly_signed_accounts == 1

      # fee_payer first (writable signer), then authority (readonly signer)
      assert Enum.at(msg.account_keys, 0) == @fee_payer
      assert Enum.at(msg.account_keys, 1) == @authority
    end

    test "multiple programs and complex account ordering" do
      ix1 = %Instruction{
        program_id: @program_a,
        accounts: [
          %AccountMeta{pubkey: @fee_payer, is_signer: true, is_writable: true},
          %AccountMeta{pubkey: @recipient, is_signer: false, is_writable: true}
        ],
        data: <<1>>
      }

      ix2 = %Instruction{
        program_id: @program_b,
        accounts: [
          %AccountMeta{pubkey: @authority, is_signer: true, is_writable: false},
          %AccountMeta{pubkey: @recipient, is_signer: false, is_writable: false}
        ],
        data: <<2>>
      }

      msg = Transaction.build_message(@fee_payer, [ix1, ix2], <<9::256>>)

      # Accounts: fee_payer (ws), authority (rs), recipient (wn - promoted by ix1),
      #           program_a (rn), program_b (rn)
      assert msg.header.num_required_signatures == 2
      assert msg.header.num_readonly_signed_accounts == 1
      assert msg.header.num_readonly_unsigned_accounts == 2

      # Compiled instructions reference correct indices
      [compiled1, compiled2] = msg.instructions
      fee_payer_idx = Enum.find_index(msg.account_keys, &(&1 == @fee_payer))
      recipient_idx = Enum.find_index(msg.account_keys, &(&1 == @recipient))
      authority_idx = Enum.find_index(msg.account_keys, &(&1 == @authority))

      assert compiled1.accounts == [fee_payer_idx, recipient_idx]
      assert compiled2.accounts == [authority_idx, recipient_idx]
    end
  end

  # ---------------------------------------------------------------------------
  # Serialization roundtrip
  # ---------------------------------------------------------------------------

  describe "serialize/deserialize roundtrip" do
    test "minimal transfer transaction" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.transfer(fee_payer, recipient, 500_000)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      # Sign with a known seed
      {_pub, seed} = Signet.Solana.Keys.from_seed(<<1::256>>)
      trx = Transaction.sign(msg, [seed])

      # Serialize
      bytes = Transaction.serialize(trx)
      assert is_binary(bytes)

      # Deserialize
      assert {:ok, decoded} = Transaction.deserialize(bytes)

      # Verify structure matches
      assert length(decoded.signatures) == 1
      assert decoded.message.header == trx.message.header
      assert decoded.message.account_keys == trx.message.account_keys
      assert decoded.message.recent_blockhash == trx.message.recent_blockhash
      assert decoded.message.instructions == trx.message.instructions
    end

    test "multi-signer transaction" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix =
        Signet.Solana.SystemProgram.create_account(
          fee_payer,
          new_account,
          1_000_000,
          165,
          owner
        )

      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      # Two signers needed
      {_pub1, seed1} = Signet.Solana.Keys.from_seed(<<1::256>>)
      {_pub2, seed2} = Signet.Solana.Keys.from_seed(<<2::256>>)
      trx = Transaction.sign(msg, [seed1, seed2])

      bytes = Transaction.serialize(trx)
      assert {:ok, decoded} = Transaction.deserialize(bytes)

      assert length(decoded.signatures) == 2
      assert decoded.message.header.num_required_signatures == 2
      assert decoded.message == trx.message
    end

    test "message-only serialize/deserialize roundtrip" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.transfer(fee_payer, recipient, 42)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      msg_bytes = Transaction.serialize_message(msg)
      assert {:ok, decoded_msg, <<>>} = Transaction.deserialize_message(msg_bytes)

      assert decoded_msg == msg
    end
  end

  # ---------------------------------------------------------------------------
  # Signing and verification
  # ---------------------------------------------------------------------------

  describe "sign/2" do
    test "produces valid Ed25519 signatures" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.transfer(fee_payer, recipient, 1_000_000)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      {pub, seed} = Signet.Solana.Keys.from_seed(<<1::256>>)
      trx = Transaction.sign(msg, [seed])

      # Verify the signature against the serialized message
      msg_bytes = Transaction.serialize_message(msg)
      [sig] = trx.signatures
      assert byte_size(sig) == 64
      assert :crypto.verify(:eddsa, :none, msg_bytes, sig, [pub, :ed25519])
    end

    test "multi-signer: each signature is valid for its key" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix =
        Signet.Solana.SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)

      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      {pub1, seed1} = Signet.Solana.Keys.from_seed(<<1::256>>)
      {pub2, seed2} = Signet.Solana.Keys.from_seed(<<2::256>>)
      trx = Transaction.sign(msg, [seed1, seed2])

      msg_bytes = Transaction.serialize_message(msg)
      [sig1, sig2] = trx.signatures
      assert :crypto.verify(:eddsa, :none, msg_bytes, sig1, [pub1, :ed25519])
      assert :crypto.verify(:eddsa, :none, msg_bytes, sig2, [pub2, :ed25519])
    end

    test "signing is deterministic" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.transfer(fee_payer, recipient, 100)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)
      {_pub, seed} = Signet.Solana.Keys.from_seed(<<1::256>>)

      trx1 = Transaction.sign(msg, [seed])
      trx2 = Transaction.sign(msg, [seed])
      assert trx1.signatures == trx2.signatures
    end
  end

  # ---------------------------------------------------------------------------
  # Partial signing (sponsored transactions)
  # ---------------------------------------------------------------------------

  describe "sign_partial/2" do
    test "fills specified positions and zero-fills the rest" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      # Only sign position 1 (new_account), leave position 0 (fee_payer) empty
      {_pub2, seed2} = Signet.Solana.Keys.from_seed(<<2::256>>)
      partial = Transaction.sign_partial(msg, %{1 => seed2})

      assert length(partial.signatures) == 2
      assert Enum.at(partial.signatures, 0) == <<0::512>>
      assert Enum.at(partial.signatures, 1) != <<0::512>>
      assert byte_size(Enum.at(partial.signatures, 1)) == 64
    end

    test "partial signature is valid for the signer's position" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      {pub2, seed2} = Signet.Solana.Keys.from_seed(<<2::256>>)
      partial = Transaction.sign_partial(msg, %{1 => seed2})

      msg_bytes = Transaction.serialize_message(msg)
      assert :crypto.verify(:eddsa, :none, msg_bytes, Enum.at(partial.signatures, 1), [pub2, :ed25519])
    end

    test "signing all positions is equivalent to sign/2" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      {_pub1, seed1} = Signet.Solana.Keys.from_seed(<<1::256>>)
      {_pub2, seed2} = Signet.Solana.Keys.from_seed(<<2::256>>)

      full = Transaction.sign(msg, [seed1, seed2])
      partial_all = Transaction.sign_partial(msg, %{0 => seed1, 1 => seed2})

      assert full.signatures == partial_all.signatures
    end
  end

  describe "add_signature/3" do
    test "replaces a zero-filled signature" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      # User signs position 1
      {_pub2, seed2} = Signet.Solana.Keys.from_seed(<<2::256>>)
      partial = Transaction.sign_partial(msg, %{1 => seed2})
      assert Enum.at(partial.signatures, 0) == <<0::512>>

      # Sponsor adds signature at position 0
      {_pub1, seed1} = Signet.Solana.Keys.from_seed(<<1::256>>)
      msg_bytes = Transaction.serialize_message(msg)
      sponsor_sig = :crypto.sign(:eddsa, :none, msg_bytes, [seed1, :ed25519])
      full = Transaction.add_signature(partial, 0, sponsor_sig)

      assert Enum.at(full.signatures, 0) == sponsor_sig
      assert Enum.at(full.signatures, 0) != <<0::512>>
      # Position 1 is unchanged
      assert Enum.at(full.signatures, 1) == Enum.at(partial.signatures, 1)
    end

    test "full sponsored transaction roundtrip: sign_partial -> serialize -> deserialize -> add_signature" do
      sponsor_pub = <<1::256>>
      user_pub = <<2::256>>
      recipient = <<3::256>>
      blockhash = <<99::256>>

      # User builds a transfer where sponsor pays fees
      ix = Signet.Solana.SystemProgram.transfer(user_pub, recipient, 500_000)
      msg = Transaction.build_message(sponsor_pub, [ix], blockhash)

      # User signs their position
      {pub2, seed2} = Signet.Solana.Keys.from_seed(<<2::256>>)
      partial = Transaction.sign_partial(msg, %{1 => seed2})

      # Serialize and "send to sponsor"
      bytes = Transaction.serialize(partial)

      # Sponsor deserializes
      {:ok, received} = Transaction.deserialize(bytes)

      # Sponsor adds their signature
      {pub1, seed1} = Signet.Solana.Keys.from_seed(<<1::256>>)
      msg_bytes = Transaction.serialize_message(received.message)
      sponsor_sig = :crypto.sign(:eddsa, :none, msg_bytes, [seed1, :ed25519])
      full = Transaction.add_signature(received, 0, sponsor_sig)

      # Verify both signatures are valid
      assert :crypto.verify(:eddsa, :none, msg_bytes, Enum.at(full.signatures, 0), [pub1, :ed25519])
      assert :crypto.verify(:eddsa, :none, msg_bytes, Enum.at(full.signatures, 1), [pub2, :ed25519])

      # Verify the full transaction serializes cleanly
      final_bytes = Transaction.serialize(full)
      assert {:ok, final} = Transaction.deserialize(final_bytes)
      assert final.signatures == full.signatures
      assert final.message == full.message
    end
  end

  # ---------------------------------------------------------------------------
  # Known byte-level tests
  # ---------------------------------------------------------------------------

  describe "known serialization" do
    test "transfer instruction data layout" do
      ix = Signet.Solana.SystemProgram.transfer(<<1::256>>, <<2::256>>, 1_000_000_000)

      # instruction index 2 (u32 LE) + lamports (u64 LE)
      assert ix.data ==
               <<2, 0, 0, 0, 0, 202, 154, 59, 0, 0, 0, 0>>

      assert byte_size(ix.data) == 12
    end

    test "create_account instruction data layout" do
      ix =
        Signet.Solana.SystemProgram.create_account(
          <<1::256>>,
          <<2::256>>,
          1_461_600,
          165,
          <<3::256>>
        )

      <<index::little-32, lamports::little-64, space::little-64, owner::binary-32>> = ix.data
      assert index == 0
      assert lamports == 1_461_600
      assert space == 165
      assert owner == <<3::256>>
    end

    test "message serialization produces deterministic bytes" do
      # Build the same message twice with same inputs
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.transfer(fee_payer, recipient, 42)

      msg1 = Transaction.build_message(fee_payer, [ix], blockhash)
      msg2 = Transaction.build_message(fee_payer, [ix], blockhash)

      assert Transaction.serialize_message(msg1) == Transaction.serialize_message(msg2)
    end

    test "transfer message has expected structure in bytes" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = Signet.Solana.SystemProgram.transfer(fee_payer, recipient, 42)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)
      bytes = Transaction.serialize_message(msg)

      # Header: 1 signer, 0 readonly signed, 1 readonly unsigned
      assert binary_part(bytes, 0, 3) == <<1, 0, 1>>

      # 3 account keys
      {3, _rest} = Transaction.decode_compact_u16(binary_part(bytes, 3, 1))

      # Verify total size:
      # 3 (header) + 1 (compact len) + 3*32 (keys) + 32 (blockhash) + 1 (compact len) +
      # 1 (program_id_idx) + 1 (compact acct len) + 2 (acct indices) + 1 (compact data len) + 12 (data)
      # = 3 + 1 + 96 + 32 + 1 + 1 + 1 + 2 + 1 + 12 = 150
      assert byte_size(bytes) == 150
    end
  end
end

defmodule Signet.Solana.KeysTest do
  use ExUnit.Case, async: true
  doctest Signet.Solana.Keys

  alias Signet.Solana.Keys

  # RFC 8032 Section 7.1 Test Vectors
  @rfc_vectors [
    # Test 1 - empty message
    %{
      seed: "9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60",
      pub: "D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A",
      address: "FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z"
    },
    # Test 2 - 1-byte message
    %{
      seed: "4CCD089B28FF96DA9DB6C346EC114E0F5B8A319F35ABA624DA8CF6ED4FB8A6FB",
      pub: "3D4017C3E843895A92B70AA74D1B7EBC9C982CCF2EC4968CC0CD55F12AF4660C"
    },
    # Test 3 - 2-byte message
    %{
      seed: "C5AA8DF43F9F837BEDB7442F31DCB7B166D38535076F094B85CE3A2E0B4458F7",
      pub: "FC51CD8E6218A1A38DA47ED00230F0580816ED13BA3303AC5DEB911548908025"
    },
    # Test SHA(abc) - 64-byte message
    %{
      seed: "833FE62409237B9D62EC77587520911E9A759CEC1D19755B7DA901B96DCA3D42",
      pub: "EC172B93AD5E563BF4932C70E1245034C35467EF2EFD4D64EBF819683467E2BF"
    }
  ]

  describe "generate_keypair/0" do
    test "returns 32-byte pub and seed" do
      {pub, seed} = Keys.generate_keypair()
      assert byte_size(pub) == 32
      assert byte_size(seed) == 32
    end

    test "generates different keypairs each time" do
      {pub1, _} = Keys.generate_keypair()
      {pub2, _} = Keys.generate_keypair()
      assert pub1 != pub2
    end
  end

  describe "from_seed/1" do
    test "derives correct pubkey for all RFC 8032 vectors" do
      for vector <- @rfc_vectors do
        seed = Base.decode16!(vector.seed)
        expected_pub = Base.decode16!(vector.pub)

        {pub, ^seed} = Keys.from_seed(seed)
        assert pub == expected_pub, "pubkey mismatch for seed #{vector.seed}"
      end
    end

    test "deterministic: same seed always gives same pubkey" do
      seed = Base.decode16!(hd(@rfc_vectors).seed)
      {pub1, _} = Keys.from_seed(seed)
      {pub2, _} = Keys.from_seed(seed)
      assert pub1 == pub2
    end

    test "all-zeros seed" do
      {pub, _seed} = Keys.from_seed(<<0::256>>)

      assert Base.encode16(pub, case: :lower) ==
               "3b6a27bcceb6a42d62a3a8d02a6f0d73653215771de243a63ac048a18b59da29"
    end
  end

  describe "from_keypair_bytes/1" do
    test "correctly imports valid keypair" do
      seed = Base.decode16!(hd(@rfc_vectors).seed)
      pub = Base.decode16!(hd(@rfc_vectors).pub)

      assert {:ok, {^pub, ^seed}} = Keys.from_keypair_bytes(seed <> pub)
    end

    test "rejects mismatched pubkey" do
      seed = Base.decode16!(hd(@rfc_vectors).seed)
      wrong_pub = :crypto.strong_rand_bytes(32)

      assert {:error, :pubkey_mismatch} = Keys.from_keypair_bytes(seed <> wrong_pub)
    end
  end

  describe "from_json/1" do
    test "parses Solana JSON keypair" do
      # Build JSON for all-zeros seed keypair
      {pub, seed} = Keys.from_seed(<<0::256>>)
      bytes = :binary.bin_to_list(seed <> pub)
      json = Jason.encode!(bytes)

      assert {:ok, {^pub, ^seed}} = Keys.from_json(json)
    end

    test "parses RFC 8032 Test 1 keypair as JSON" do
      seed = Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")
      pub = Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")

      json = Jason.encode!(:binary.bin_to_list(seed <> pub))
      assert {:ok, {^pub, ^seed}} = Keys.from_json(json)
    end

    test "rejects invalid JSON" do
      assert {:error, _} = Keys.from_json("not json")
    end

    test "rejects wrong length" do
      json = Jason.encode!(Enum.to_list(1..32))
      assert {:error, :invalid_length} = Keys.from_json(json)
    end

    test "rejects mismatched pubkey in JSON" do
      seed = Base.decode16!(hd(@rfc_vectors).seed)
      wrong_pub = :crypto.strong_rand_bytes(32)
      json = Jason.encode!(:binary.bin_to_list(seed <> wrong_pub))

      assert {:error, :pubkey_mismatch} = Keys.from_json(json)
    end
  end

  describe "to_address/1" do
    test "RFC 8032 Test 1" do
      pub = Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")
      assert Keys.to_address(pub) == "FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z"
    end

    test "all-zeros seed" do
      {pub, _} = Keys.from_seed(<<0::256>>)
      assert Keys.to_address(pub) == "4zvwRjXUKGfvwnParsHAS3HuSVzV5cA4McphgmoCtajS"
    end

    test "roundtrip: address decodes back to pubkey" do
      {pub, _} = Keys.generate_keypair()
      address = Keys.to_address(pub)
      assert Signet.Base58.decode!(address) == pub
    end
  end
end

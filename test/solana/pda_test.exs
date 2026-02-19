defmodule Signet.Solana.PDATest do
  use ExUnit.Case, async: true
  doctest Signet.Solana.PDA

  alias Signet.Solana.PDA

  describe "on_curve?/1" do
    test "known Ed25519 public keys are on curve" do
      # RFC 8032 test vectors - all valid Ed25519 pubkeys
      pubkeys = [
        "D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A",
        "3D4017C3E843895A92B70AA74D1B7EBC9C982CCF2EC4968CC0CD55F12AF4660C",
        "FC51CD8E6218A1A38DA47ED00230F0580816ED13BA3303AC5DEB911548908025",
        "EC172B93AD5E563BF4932C70E1245034C35467EF2EFD4D64EBF819683467E2BF"
      ]

      for hex <- pubkeys do
        pub = Base.decode16!(hex)
        assert PDA.on_curve?(pub), "Expected #{hex} to be on curve"
      end
    end

    test "freshly generated keypairs are on curve" do
      for _ <- 1..10 do
        {pub, _} = Signet.Solana.Keys.generate_keypair()
        assert PDA.on_curve?(pub)
      end
    end

    test "PDA outputs are not on curve" do
      pdas = [
        PDA.find_program_address!(["hello"], <<0::256>>),
        PDA.find_program_address!([], <<0::256>>),
        PDA.find_program_address!(["a", "b", "c"], <<1::256>>),
        PDA.find_program_address!([<<42::256>>], <<99::256>>)
      ]

      for {addr, _bump} <- pdas do
        refute PDA.on_curve?(addr)
      end
    end

    test "roughly half of random SHA-256 outputs are on curve" do
      on_count =
        Enum.count(1..100, fn i ->
          hash = :crypto.hash(:sha256, <<i::256>>)
          PDA.on_curve?(hash)
        end)

      # Should be roughly 50%, allow wide margin
      assert on_count > 20 and on_count < 80,
             "Expected ~50 on-curve, got #{on_count}"
    end
  end

  describe "find_program_address/2" do
    test "returns {:ok, {address, bump}}" do
      assert {:ok, {address, bump}} = PDA.find_program_address(["test"], <<0::256>>)
      assert byte_size(address) == 32
      assert bump >= 0 and bump <= 255
    end

    test "result is not on curve" do
      {:ok, {address, _bump}} = PDA.find_program_address(["test"], <<0::256>>)
      refute PDA.on_curve?(address)
    end

    test "is deterministic" do
      assert PDA.find_program_address(["seed"], <<0::256>>) ==
               PDA.find_program_address(["seed"], <<0::256>>)
    end

    test "different seeds produce different addresses" do
      {:ok, {addr1, _}} = PDA.find_program_address(["hello"], <<0::256>>)
      {:ok, {addr2, _}} = PDA.find_program_address(["world"], <<0::256>>)
      assert addr1 != addr2
    end

    test "different programs produce different addresses" do
      {:ok, {addr1, _}} = PDA.find_program_address(["test"], <<0::256>>)
      {:ok, {addr2, _}} = PDA.find_program_address(["test"], <<1::256>>)
      assert addr1 != addr2
    end

    test "works with empty seeds" do
      assert {:ok, {address, bump}} = PDA.find_program_address([], <<0::256>>)
      assert byte_size(address) == 32
      assert bump >= 0
    end

    test "works with binary seeds (pubkeys)" do
      {pub, _} = Signet.Solana.Keys.generate_keypair()
      assert {:ok, {address, _bump}} = PDA.find_program_address([pub], <<0::256>>)
      assert byte_size(address) == 32
    end

    test "works with multiple seeds" do
      assert {:ok, {address, bump}} = PDA.find_program_address(["hello", "world"], <<0::256>>)
      assert byte_size(address) == 32
      assert bump >= 0
    end

    test "bump may not always be 255" do
      bumps =
        Enum.map(0..20, fn i ->
          {:ok, {_, bump}} = PDA.find_program_address([<<i>>], <<0::256>>)
          bump
        end)

      assert Enum.any?(bumps, &(&1 < 255)),
             "Expected at least one bump < 255 in 20 tries"
    end
  end

  describe "find_program_address!/2" do
    test "returns {address, bump} directly" do
      {address, bump} = PDA.find_program_address!(["test"], <<0::256>>)
      assert byte_size(address) == 32
      assert bump >= 0 and bump <= 255
    end

    test "matches find_program_address/2" do
      {:ok, expected} = PDA.find_program_address(["test"], <<0::256>>)
      assert PDA.find_program_address!(["test"], <<0::256>>) == expected
    end
  end

  describe "create_program_address/2" do
    test "returns address matching find_program_address" do
      {expected, bump} = PDA.find_program_address!(["test"], <<0::256>>)
      assert PDA.create_program_address(["test", <<bump>>], <<0::256>>) == {:ok, expected}
    end

    test "wrong bump returns :on_curve or different address" do
      {_expected, bump} = PDA.find_program_address!(["test"], <<0::256>>)

      if bump < 255 do
        result = PDA.create_program_address(["test", <<bump + 1>>], <<0::256>>)
        assert result == {:error, :on_curve} or
                 (match?({:ok, addr} when addr != _expected, result))
      end
    end
  end
end

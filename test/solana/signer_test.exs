defmodule Signet.Solana.SignerTest do
  use ExUnit.Case, async: true
  doctest Signet.Solana.Signer
  doctest Signet.Solana.Signer.Ed25519

  alias Signet.Solana.Signer
  alias Signet.Solana.Signer.Ed25519, as: Ed25519Backend

  # RFC 8032 Section 7.1 Test Vectors
  @test_vectors [
    # Test 1 - empty message
    %{
      seed: "9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60",
      pub: "D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A",
      message: "",
      signature:
        "E5564300C360AC729086E2CC806E828A84877F1EB8E5D974D873E065224901555FB8821590A33BACC61E39701CF9B46BD25BF5F0595BBE24655141438E7A100B"
    },
    # Test 2 - 1-byte message
    %{
      seed: "4CCD089B28FF96DA9DB6C346EC114E0F5B8A319F35ABA624DA8CF6ED4FB8A6FB",
      pub: "3D4017C3E843895A92B70AA74D1B7EBC9C982CCF2EC4968CC0CD55F12AF4660C",
      message: "72",
      signature:
        "92A009A9F0D4CAB8720E820B5F642540A2B27B5416503F8FB3762223EBDB69DA085AC1E43E15996E458F3613D0F11D8C387B2EAEB4302AEEB00D291612BB0C00"
    },
    # Test 3 - 2-byte message
    %{
      seed: "C5AA8DF43F9F837BEDB7442F31DCB7B166D38535076F094B85CE3A2E0B4458F7",
      pub: "FC51CD8E6218A1A38DA47ED00230F0580816ED13BA3303AC5DEB911548908025",
      message: "AF82",
      signature:
        "6291D657DEEC24024827E69C3ABE01A30CE548A284743A445E3680D7DB5AC3AC18FF9B538D16F290AE67F760984DC6594A7C15E9716ED28DC027BECEEA1EC40A"
    },
    # Test SHA(abc) - 64-byte message
    %{
      seed: "833FE62409237B9D62EC77587520911E9A759CEC1D19755B7DA901B96DCA3D42",
      pub: "EC172B93AD5E563BF4932C70E1245034C35467EF2EFD4D64EBF819683467E2BF",
      message:
        "DDAF35A193617ABACC417349AE20413112E6FA4E89A97EA20A9EEEE64B55D39A2192992A274FC1A836BA3C23A3FEEBBD454D4423643CE80E2A9AC94FA54CA49F",
      signature:
        "DC2A4459E7369633A52B1BF277839A00201009A3EFBF3ECB69BEA2186C26B58909351FC9AC90B3ECFDFBC7C66431E0303DCA179C138AC17AD9BEF1177331A704"
    }
  ]

  describe "Ed25519 backend" do
    test "get_address returns correct pubkey for all RFC 8032 vectors" do
      for v <- @test_vectors do
        seed = Base.decode16!(v.seed)
        expected_pub = Base.decode16!(v.pub)

        assert {:ok, ^expected_pub} = Ed25519Backend.get_address(seed)
      end
    end

    test "sign produces correct signatures for all RFC 8032 vectors" do
      for v <- @test_vectors do
        seed = Base.decode16!(v.seed)
        message = Base.decode16!(v.message)
        expected_sig = Base.decode16!(v.signature)

        {:ok, sig} = Ed25519Backend.sign(message, seed)

        assert sig == expected_sig,
               "signature mismatch for vector with seed #{v.seed}"
      end
    end

    test "signature is exactly 64 bytes" do
      seed = Base.decode16!(hd(@test_vectors).seed)
      {:ok, sig} = Ed25519Backend.sign("hello world", seed)
      assert byte_size(sig) == 64
    end

    test "signing is deterministic" do
      seed = Base.decode16!(hd(@test_vectors).seed)
      {:ok, sig1} = Ed25519Backend.sign("hello", seed)
      {:ok, sig2} = Ed25519Backend.sign("hello", seed)
      assert sig1 == sig2
    end
  end

  describe "verify/3" do
    test "verifies correct signatures for all RFC 8032 vectors" do
      for v <- @test_vectors do
        pub = Base.decode16!(v.pub)
        message = Base.decode16!(v.message)
        signature = Base.decode16!(v.signature)

        assert Signer.verify(message, signature, pub),
               "verification failed for vector with seed #{v.seed}"
      end
    end

    test "rejects wrong pubkey" do
      v = hd(@test_vectors)
      message = Base.decode16!(v.message)
      signature = Base.decode16!(v.signature)
      wrong_pub = :crypto.strong_rand_bytes(32)

      refute Signer.verify(message, signature, wrong_pub)
    end

    test "rejects tampered message" do
      v = hd(@test_vectors)
      pub = Base.decode16!(v.pub)
      signature = Base.decode16!(v.signature)

      refute Signer.verify("tampered", signature, pub)
    end

    test "rejects tampered signature" do
      v = hd(@test_vectors)
      pub = Base.decode16!(v.pub)
      message = Base.decode16!(v.message)
      tampered_sig = :crypto.strong_rand_bytes(64)

      refute Signer.verify(message, tampered_sig, pub)
    end
  end

  describe "GenServer signer" do
    test "sign returns valid signature" do
      signer = Signet.Solana.Test.Signer.start_signer()
      {:ok, sig} = Signer.sign("test message", signer)

      assert byte_size(sig) == 64

      # Verify with known pubkey
      pub =
        Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")

      assert Signer.verify("test message", sig, pub)
    end

    test "address returns correct pubkey" do
      signer = Signet.Solana.Test.Signer.start_signer()
      address = Signer.address(signer)

      expected =
        Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")

      assert address == expected
    end

    test "address is cached (second call returns same value)" do
      signer = Signet.Solana.Test.Signer.start_signer()
      addr1 = Signer.address(signer)
      addr2 = Signer.address(signer)
      assert addr1 == addr2
    end

    test "multiple signers with different names" do
      signer1 = Signet.Solana.Test.Signer.start_signer()
      signer2 = Signet.Solana.Test.Signer.start_signer()

      # Both work independently
      {:ok, sig1} = Signer.sign("msg", signer1)
      {:ok, sig2} = Signer.sign("msg", signer2)

      # Same seed = same signature (deterministic)
      assert sig1 == sig2
    end

    test "sign + verify roundtrip through GenServer" do
      signer = Signet.Solana.Test.Signer.start_signer()
      pub = Signer.address(signer)
      {:ok, sig} = Signer.sign("roundtrip test", signer)

      assert Signer.verify("roundtrip test", sig, pub)
      refute Signer.verify("different message", sig, pub)
    end
  end
end

defmodule Signet.Base58Test do
  use ExUnit.Case, async: true
  use Signet.Base58
  doctest Signet.Base58

  describe "encode/1" do
    test "empty binary" do
      assert Signet.Base58.encode(<<>>) == ""
    end

    test "single zero byte" do
      assert Signet.Base58.encode(<<0>>) == "1"
    end

    test "multiple leading zero bytes" do
      assert Signet.Base58.encode(<<0, 0, 0>>) == "111"
    end

    # IETF draft-msporny-base58-03 test vectors
    test "IETF: Hello World!" do
      assert Signet.Base58.encode("Hello World!") == "2NEpo7TZRRrLZSi2U"
    end

    test "IETF: The quick brown fox..." do
      assert Signet.Base58.encode("The quick brown fox jumps over the lazy dog.") ==
               "USm3fpXnKG5EUBx2ndxBDMPVciP5hGey2Jh4NDv6gmeo1LkMeiKrLJUUBk6Z"
    end

    test "IETF: leading zeros" do
      assert Signet.Base58.encode(Base.decode16!("0000287FB4CD", case: :upper)) == "11233QC4"
    end

    # Bitcoin Core test vectors (src/test/data/base58_encode_decode.json)
    test "Bitcoin Core vectors" do
      vectors = [
        {"61", "2g"},
        {"626262", "a3gV"},
        {"636363", "aPEr"},
        {"516B6FCD0F", "ABnLTmg"},
        {"BF4F89001E670274DD", "3SEo3LWLoPntC"},
        {"572E4794", "3EFU7m"},
        {"ECAC89CAD93923C02321", "EJDM8drfXA6uyA"},
        {"10C8511E", "Rt5zm"},
        {"00000000000000000000", "1111111111"},
        {"00EB15231DFCEB60925886B67D065299925915AEB172C06647",
         "1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L"},
        {"000111D38E5FC9071FFCD20B4A763CC9AE4F252BB4E48FD66A835E252ADA93FF480D6DD43DC62A641155A5",
         "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"}
      ]

      for {hex, expected_b58} <- vectors do
        binary = Base.decode16!(hex, case: :upper)
        assert Signet.Base58.encode(binary) == expected_b58, "encode failed for hex #{hex}"
      end
    end

    # Boundary tests near 58^5
    test "boundary: zzzzy" do
      assert Signet.Base58.encode(Base.decode16!("271F359E", case: :upper)) == "zzzzy"
    end

    test "boundary: zzzzz (58^5 - 1)" do
      assert Signet.Base58.encode(Base.decode16!("271F359F", case: :upper)) == "zzzzz"
    end

    test "boundary: 211111 (58^5)" do
      assert Signet.Base58.encode(Base.decode16!("271F35A0", case: :upper)) == "211111"
    end

    # Solana program addresses
    test "Solana System Program (32 zero bytes)" do
      assert Signet.Base58.encode(<<0::256>>) == "11111111111111111111111111111111"
    end

    test "Solana Token Program" do
      binary =
        Base.decode16!("06DDF6E1D765A193D9CBE146CEEB79AC1CB485ED5F5B37913A8CF5857EFF00A9",
          case: :upper
        )

      assert Signet.Base58.encode(binary) == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
    end

    test "Solana Associated Token Account Program" do
      binary =
        Base.decode16!("8C97258F4E2489F1BB3D1029148E0D830B5A1399DAFF1084048E7BD8DBE9F859",
          case: :upper
        )

      assert Signet.Base58.encode(binary) ==
               "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL"
    end

    test "Solana Token 2022 Program" do
      binary =
        Base.decode16!("06DDF6E1EE758FDE18425DBCE46CCDDAB61AFC4D83B90D27FEBDF928D8A18BFC",
          case: :upper
        )

      assert Signet.Base58.encode(binary) == "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
    end
  end

  describe "decode/1" do
    test "empty string" do
      assert Signet.Base58.decode("") == {:ok, <<>>}
    end

    test "single 1" do
      assert Signet.Base58.decode("1") == {:ok, <<0>>}
    end

    test "multiple leading 1s" do
      assert Signet.Base58.decode("111") == {:ok, <<0, 0, 0>>}
    end

    # IETF draft vectors (decode direction)
    test "IETF: Hello World!" do
      assert Signet.Base58.decode("2NEpo7TZRRrLZSi2U") == {:ok, "Hello World!"}
    end

    test "IETF: The quick brown fox..." do
      assert Signet.Base58.decode("USm3fpXnKG5EUBx2ndxBDMPVciP5hGey2Jh4NDv6gmeo1LkMeiKrLJUUBk6Z") ==
               {:ok, "The quick brown fox jumps over the lazy dog."}
    end

    test "IETF: leading zeros" do
      {:ok, result} = Signet.Base58.decode("11233QC4")
      assert result == Base.decode16!("0000287FB4CD", case: :upper)
    end

    # Bitcoin Core vectors (decode direction)
    test "Bitcoin Core vectors" do
      vectors = [
        {"2g", "61"},
        {"a3gV", "626262"},
        {"aPEr", "636363"},
        {"ABnLTmg", "516B6FCD0F"},
        {"3SEo3LWLoPntC", "BF4F89001E670274DD"},
        {"3EFU7m", "572E4794"},
        {"EJDM8drfXA6uyA", "ECAC89CAD93923C02321"},
        {"Rt5zm", "10C8511E"},
        {"1111111111", "00000000000000000000"},
        {"1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L",
         "00EB15231DFCEB60925886B67D065299925915AEB172C06647"},
        {"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz",
         "000111D38E5FC9071FFCD20B4A763CC9AE4F252BB4E48FD66A835E252ADA93FF480D6DD43DC62A641155A5"}
      ]

      for {b58, expected_hex} <- vectors do
        expected = Base.decode16!(expected_hex, case: :upper)
        assert Signet.Base58.decode(b58) == {:ok, expected}, "decode failed for #{b58}"
      end
    end

    # Solana addresses
    test "Solana System Program" do
      assert Signet.Base58.decode("11111111111111111111111111111111") == {:ok, <<0::256>>}
    end

    test "Solana Token Program" do
      expected =
        Base.decode16!("06DDF6E1D765A193D9CBE146CEEB79AC1CB485ED5F5B37913A8CF5857EFF00A9",
          case: :upper
        )

      assert Signet.Base58.decode("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA") ==
               {:ok, expected}
    end

    # Error cases
    test "invalid character: 0" do
      assert Signet.Base58.decode("abc0def") == {:error, {:invalid_character, "0"}}
    end

    test "invalid character: O" do
      assert Signet.Base58.decode("O") == {:error, {:invalid_character, "O"}}
    end

    test "invalid character: I" do
      assert Signet.Base58.decode("I") == {:error, {:invalid_character, "I"}}
    end

    test "invalid character: l" do
      assert Signet.Base58.decode("l") == {:error, {:invalid_character, "l"}}
    end

    test "invalid character: +" do
      assert Signet.Base58.decode("+") == {:error, {:invalid_character, "+"}}
    end

    test "invalid character: /" do
      assert Signet.Base58.decode("/") == {:error, {:invalid_character, "/"}}
    end
  end

  describe "decode!/1" do
    test "valid input" do
      assert Signet.Base58.decode!("2g") == <<0x61>>
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, ~r/invalid Base58/, fn ->
        Signet.Base58.decode!("0invalid")
      end
    end
  end

  describe "roundtrip" do
    test "encode then decode for all Bitcoin Core vectors" do
      hexes = [
        "61",
        "626262",
        "636363",
        "516B6FCD0F",
        "BF4F89001E670274DD",
        "572E4794",
        "ECAC89CAD93923C02321",
        "10C8511E",
        "00000000000000000000",
        "00EB15231DFCEB60925886B67D065299925915AEB172C06647"
      ]

      for hex <- hexes do
        binary = Base.decode16!(hex, case: :upper)
        assert Signet.Base58.decode!(Signet.Base58.encode(binary)) == binary
      end
    end

    test "roundtrip with various binary sizes" do
      for size <- [0, 1, 2, 4, 8, 16, 20, 32, 64] do
        binary = :crypto.strong_rand_bytes(size)
        assert Signet.Base58.decode!(Signet.Base58.encode(binary)) == binary
      end
    end

    test "roundtrip preserves leading zero bytes" do
      for n <- 0..5 do
        binary = :binary.copy(<<0>>, n) <> :crypto.strong_rand_bytes(8)
        assert Signet.Base58.decode!(Signet.Base58.encode(binary)) == binary
      end
    end
  end
end

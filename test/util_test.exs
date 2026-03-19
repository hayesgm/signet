defmodule Signet.UtilTest do
  use ExUnit.Case, async: true
  doctest Signet.Util
  doctest Signet.Util.RecoveryBit

  describe "checksum_address/1" do
    test "handles a 20-byte binary whose first two bytes are ASCII '0x'" do
      # <<0x30, 0x78>> is ASCII "0x". When a raw 20-byte address starts with
      # these bytes, checksum_address/1 must not confuse it with a hex string.
      address = <<0x30, 0x78, 0::144>>
      result = Signet.Util.checksum_address(address)
      assert is_binary(result)
      assert String.starts_with?(result, "0x")
      assert byte_size(result) == 42
    end

    test "checksums a hex string input" do
      assert Signet.Util.checksum_address("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed") ==
               "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    end
  end
end

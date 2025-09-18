defmodule Signet.RPCTest do
  use ExUnit.Case, async: true
  use Signet.Hex
  doctest Signet.RPC

  describe "error_data handling in decode_response" do

    test "handles binary error_data (hex-encoded) - existing behavior" do
      # Test call to address 0x000000000000000000000000000000000000000A which returns simple encoded error
      result = Signet.RPC.send_rpc("eth_call", [%{"to" => "0x000000000000000000000000000000000000000A"}, "latest"])

      assert {:error, error_data} = result
      assert error_data.code == 3
      assert error_data.message == "execution reverted"
      assert error_data.revert == ~h[3d738b2e]
    end

    test "handles map error_data directly - new functionality" do
      # Test call to address 0x000000000000000000000000000000000000000E which returns map error data
      result = Signet.RPC.send_rpc("eth_call", [%{"to" => "0x000000000000000000000000000000000000000E"}, "latest"])

      assert {:error, error_data} = result
      assert error_data.code == 3
      assert error_data.message == "execution reverted"
      assert error_data["custom_field"] == "custom_value"
      assert error_data["nested"]["key"] == "value"
    end

    test "handles invalid hex error_data gracefully" do
      # Test call to address 0x000000000000000000000000000000000000000F which returns invalid hex
      result = Signet.RPC.send_rpc("eth_call", [%{"to" => "0x000000000000000000000000000000000000000F"}, "latest"])

      assert {:error, error_data} = result
      assert error_data.code == 3
      assert error_data.message == "execution reverted"
      # Should not have revert data for invalid hex
      refute Map.has_key?(error_data, :revert)
    end

    test "handles numeric error_data" do
      # Test call to address 0x0000000000000000000000000000000000000010 which returns numeric error data
      result = Signet.RPC.send_rpc("eth_call", [%{"to" => "0x0000000000000000000000000000000000000010"}, "latest"])

      assert {:error, error_data} = result
      assert error_data.code == 3
      assert error_data.message == "execution reverted"
      # Should only contain basic error fields for unsupported data types
      refute Map.has_key?(error_data, :revert)
    end

    test "handles blank hex error_data" do
      # Test call to address 0x000000000000000000000000000000000000000C which returns blank data
      result = Signet.RPC.send_rpc("eth_call", [%{"to" => "0x000000000000000000000000000000000000000C"}, "latest"])

      assert {:error, error_data} = result
      assert error_data.code == 3
      assert error_data.message == "execution reverted"
      # Should have empty revert data for blank hex
      assert error_data.revert == ""
    end
  end
end

defmodule Signet.Test.SleuthHandler do
  @moduledoc ~S"""
  Module to handle sending back sleuth responses to our unit tests.

  Note: this could clearly be abstracted to be a little nicer, but it's
        perfectly adequate the way it is now, I reckon.
  """
  use Signet.Hex

  @block_number_query Signet.Contract.BlockNumber.bytecode()

  defp handle_call(@block_number_query, calldata) do
    case Signet.Contract.BlockNumber.decode_call(calldata) do
      {:ok, "query", _} ->
        encode_sleuth(Signet.Contract.BlockNumber.query_selector(), {2})

      {:ok, "queryTwo", _} ->
      encode_sleuth(Signet.Contract.BlockNumber.query_two_selector(), {2, 3})

      {:ok, "queryThree", _} ->
        encode_sleuth(Signet.Contract.BlockNumber.query_three_selector(), {2})

      {:ok, "queryFour", _} ->
        encode_sleuth(Signet.Contract.BlockNumber.query_four_selector(), {~h[0x010203], ~h[0x0000000000000000000000000000000000000001]})

      {:ok, "queryCool", _} ->
        encode_sleuth(Signet.Contract.BlockNumber.query_cool_selector(), {{"hi", [1, 2, 3], {"meow"}}})
      
      _ ->
        raise "Unknown Sleuth query call" 
    end
  end

  defp handle_call(query, _calldata) do
    raise "Unknown sleuth query: #{to_hex(query)}"
  end

  def eth_call(%{"data" => data_hex}, _block) do
    data = from_hex!(data_hex)

    cond do
      String.contains?(data, ~h[0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF00000000]) ->
        "0x"

      String.contains?(data, ~h[0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF00000001]) ->
        {:error,
         %{
           "code" => 3,
           "message" => "unexpected"
         }}

      true ->
        [query, calldata] = Signet.Contract.Sleuth.decode_query_call(data)

        Base.encode16(handle_call(query, calldata))
    end
  end

  defp encode_sleuth(query_selector, values) do
    return_selector = %ABI.FunctionSelector{
      types: [%{type: {:tuple, query_selector.returns}}]
    }

    query_resp = ABI.TypeEncoder.encode([values], return_selector)
    ABI.encode("(bytes)", [{query_resp}])
  end
end

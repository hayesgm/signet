defmodule Signet.FilterTest do
  use ExUnit.Case, async: true
  doctest Signet.Filter

  use Signet.Hex

  test "add a filter and get events" do
    extra_data = %{some_key: "some value"}

    {:ok, _filter_pid} =
      Signet.Filter.start_link(
        name: MyFilter,
        address: <<1::160>>,
        events: ["Transfer(address indexed from, address indexed to, uint amount)"],
        check_delay: 300,
        extra_data: extra_data
      )

    Signet.Filter.listen(MyFilter)

    :timer.sleep(600)

    log =
      Signet.Filter.Log.deserialize(%{
        "address" => "0xb5a5f22694352c15b00323844ad545abb2b11028",
        "blockHash" => "0x99e8663c7b6d8bba3c7627a17d774238eae3e793dee30008debb2699666657de",
        "blockNumber" => "0x5d12ab",
        "data" => "0x00000000000000000000000000000000000000000000000000000004a817c800",
        "logIndex" => "0x0",
        "removed" => false,
        "topics" => [
          "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
          "0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8",
          "0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea"
        ],
        "transactionHash" => "0xa74c2432c9cf7dbb875a385a2411fd8f13ca9ec12216864b1a1ead3c99de99cd",
        "transactionIndex" => "0x3"
      })
      |> Map.put(:extra_data, extra_data)

    assert_received {:event,
                     {"Transfer",
                      %{
                        "amount" => 20_000_000_000,
                        "from" => ~h[b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
                        "to" => ~h[7795126b3ae468f44c901287de98594198ce38ea]
                      }}, ^log}

    assert_received {:log, ^log}
  end

  # TODO: Test expired filter
end

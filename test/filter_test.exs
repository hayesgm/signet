defmodule Signet.FilterTest do
  use ExUnit.Case, async: true
  doctest Signet.Filter

  test "add a filter and get events" do
    {:ok, _filter_pid} =
      Signet.Filter.start_link([
        MyFilter,
        <<1::160>>,
        [],
        ["Transfer(address indexed from, address indexed to, uint amount)"]
      ])

    Signet.Filter.listen(MyFilter)

    :timer.sleep(6000)

    assert_received {:event,
                     {"Transfer",
                      %{
                        "amount" => 20_000_000_000,
                        "from" => [
                          <<178, 183, 193, 121, 95, 25, 251, 194, 143, 218, 119, 169, 94, 89, 237,
                            187, 139, 55, 9, 200>>
                        ],
                        "to" => [
                          <<119, 149, 18, 107, 58, 228, 104, 244, 76, 144, 18, 135, 222, 152, 89,
                            65, 152, 206, 56, 234>>
                        ]
                      }}}

    assert_received {
      :log,
      %{
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
      }
    }
  end
end

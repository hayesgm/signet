defmodule SleuthTest do
  use ExUnit.Case
  use Signet.Hex
  alias Signet.Sleuth
  doctest Sleuth

  describe "BlockNumber" do
    test "query()" do
      assert {:ok, %{"blockNumber" => 2}} ==
               Signet.Sleuth.query(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query(),
                 Signet.Contract.BlockNumber.query_selector()
               )

      v2_case = fn opts ->
        Signet.Sleuth.query_v2(
          Signet.Contract.BlockNumber.bytecode(),
          Signet.Contract.BlockNumber.encode_query(),
          Signet.Contract.BlockNumber.query_selector(),
          opts
        )
      end

      assert {:ok, [2]} == v2_case.([])
      assert {:ok, [block_number: 2]} == v2_case.(named_returns: true)
    end

    test "query() failure with trace" do
      assert {:error,
              %{
                code: 3,
                message: "execution reverted",
                trace: _
              }} =
               Signet.Sleuth.query(
                 ~h[],
                 ~h[0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF00000001],
                 Signet.Contract.BlockNumber.query_selector(),
                 trace_reverts: true
               )
    end

    test "query() failure with debug trace" do
      assert {:error,
              %{
                code: 3,
                message: "execution reverted",
                trace: _
              }} =
               Signet.Sleuth.query(
                 ~h[],
                 ~h[0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF00000001],
                 Signet.Contract.BlockNumber.query_selector(),
                 trace_reverts: true,
                 debug_trace: true
               )
    end

    test "query_by() via mod/fun" do
      assert {:ok, %{"blockNumber" => 2}} ==
               Signet.Sleuth.query_by(
                 Signet.Contract.BlockNumber,
                 :query
               )
    end

    test "query_by() via mod" do
      assert {:ok, %{"blockNumber" => 2}} ==
               Signet.Sleuth.query_by(Signet.Contract.BlockNumber)
    end

    test "queryTwo()" do
      assert {:ok, %{"x" => 2, "y" => 3}} ==
               Signet.Sleuth.query(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_two(),
                 Signet.Contract.BlockNumber.query_two_selector()
               )

      v2_case = fn opts ->
        Signet.Sleuth.query_v2(
          Signet.Contract.BlockNumber.bytecode(),
          Signet.Contract.BlockNumber.encode_query_two(),
          Signet.Contract.BlockNumber.query_two_selector(),
          opts
        )
      end

      assert {:ok, [2, 3]} == v2_case.([])
      assert {:ok, [x: 2, y: 3]} == v2_case.(named_returns: true)
    end

    test "queryTwo() - annotated" do
      assert {:ok, %{"x" => {{:uint, 256}, 2}, "y" => {{:uint, 256}, 3}}} ==
               Signet.Sleuth.query_annotated(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_two(),
                 Signet.Contract.BlockNumber.query_two_selector()
               )

      v2_annotated_case = fn opts ->
        Signet.Sleuth.query_v2_annotated(
          Signet.Contract.BlockNumber.bytecode(),
          Signet.Contract.BlockNumber.encode_query_two(),
          Signet.Contract.BlockNumber.query_two_selector(),
          opts
        )
      end

      assert {:ok, [{{:uint, 256}, 2}, {{:uint, 256}, 3}]} == v2_annotated_case.([])

      assert {:ok, [x: {{:uint, 256}, 2}, y: {{:uint, 256}, 3}]} ==
               v2_annotated_case.(named_returns: true)
    end

    test "queryThree()" do
      assert {:ok, 2} ==
               Signet.Sleuth.query(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_three(),
                 Signet.Contract.BlockNumber.query_three_selector()
               )

      v2_case = fn opts ->
        Signet.Sleuth.query_v2(
          Signet.Contract.BlockNumber.bytecode(),
          Signet.Contract.BlockNumber.encode_query_three(),
          Signet.Contract.BlockNumber.query_three_selector(),
          opts
        )
      end

      assert {:ok, [2]} == v2_case.([])
      assert {:ok, [__unnamed__: 2]} == v2_case.(named_returns: true)
    end

    test "queryThree() - annotated" do
      assert {:ok, {{:uint, 256}, 2}} ==
               Signet.Sleuth.query_annotated(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_three(),
                 Signet.Contract.BlockNumber.query_three_selector()
               )

      assert {:ok, [{{:uint, 256}, 2}]} ==
               Signet.Sleuth.query_v2_annotated(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_three(),
                 Signet.Contract.BlockNumber.query_three_selector()
               )
    end

    test "queryFour()" do
      assert {:ok, %{"var0" => ~h[0x010203], "var1" => <<1::160>>}} ==
               Signet.Sleuth.query(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_four(),
                 Signet.Contract.BlockNumber.query_four_selector()
               )

      v2_case = fn opts ->
        Signet.Sleuth.query_v2(
          Signet.Contract.BlockNumber.bytecode(),
          Signet.Contract.BlockNumber.encode_query_four(),
          Signet.Contract.BlockNumber.query_four_selector(),
          opts
        )
      end

      assert {:ok, [~h[0x010203], <<1::160>>]} == v2_case.([])

      assert {:ok, [__unnamed__: ~h[0x010203], __unnamed__: <<1::160>>]} ==
               v2_case.(named_returns: true)
    end

    test "queryFour() - no decode binaries" do
      assert {:ok,
              %{"var0" => "0x010203", "var1" => "0x0000000000000000000000000000000000000001"}} ==
               Signet.Sleuth.query(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_four(),
                 Signet.Contract.BlockNumber.query_four_selector(),
                 decode_binaries: false
               )

      v2_case = fn opts ->
        Signet.Sleuth.query_v2(
          Signet.Contract.BlockNumber.bytecode(),
          Signet.Contract.BlockNumber.encode_query_four(),
          Signet.Contract.BlockNumber.query_four_selector(),
          opts
        )
      end

      assert {:ok, ["0x010203", "0x0000000000000000000000000000000000000001"]} ==
               v2_case.(decode_binaries: false)

      assert {:ok,
              [__unnamed__: "0x010203", __unnamed__: "0x0000000000000000000000000000000000000001"]} ==
               v2_case.(decode_binaries: false, named_returns: true)
    end

    test "queryCool()" do
      assert {:ok,
              %{
                "cool" => %{
                  "fun" => %{"cat" => "meow"},
                  "x" => "hi",
                  "ys" => [1, 2, 3]
                }
              }} ==
               Signet.Sleuth.query(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_cool(),
                 Signet.Contract.BlockNumber.query_cool_selector()
               )

      v2_case = fn opts ->
        Signet.Sleuth.query_v2(
          Signet.Contract.BlockNumber.bytecode(),
          Signet.Contract.BlockNumber.encode_query_cool(),
          Signet.Contract.BlockNumber.query_cool_selector(),
          opts
        )
      end

      assert {:ok,
              [
                %{
                  fun: %{cat: "meow"},
                  x: "hi",
                  ys: [1, 2, 3]
                }
              ]} == v2_case.([])

      assert {:ok,
              [
                %{
                  "fun" => %{"cat" => "meow"},
                  "x" => "hi",
                  "ys" => [1, 2, 3]
                }
              ]} == v2_case.(decode_structs: false)

      assert {:ok,
              [
                cool: %{
                  fun: %{cat: "meow"},
                  x: "hi",
                  ys: [1, 2, 3]
                }
              ]} == v2_case.(named_returns: true)

      assert {:ok,
              [
                cool: %{
                  "fun" => %{"cat" => "meow"},
                  "x" => "hi",
                  "ys" => [1, 2, 3]
                }
              ]} == v2_case.(named_returns: true, decode_structs: false)
    end

    test "queryCool() - annotated" do
      assert {:ok,
              %{
                "cool" => %{
                  "fun" => %{"cat" => {:string, "meow"}},
                  "x" => {:string, "hi"},
                  "ys" => [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              }} ==
               Signet.Sleuth.query_annotated(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_cool(),
                 Signet.Contract.BlockNumber.query_cool_selector()
               )

      v2_annotated_case = fn opts ->
        Signet.Sleuth.query_v2_annotated(
          Signet.Contract.BlockNumber.bytecode(),
          Signet.Contract.BlockNumber.encode_query_cool(),
          Signet.Contract.BlockNumber.query_cool_selector(),
          opts
        )
      end

      assert {:ok,
              [
                %{
                  fun: %{cat: {:string, "meow"}},
                  x: {:string, "hi"},
                  ys: [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              ]} == v2_annotated_case.([])

      assert {:ok,
              [
                %{
                  "fun" => %{"cat" => {:string, "meow"}},
                  "x" => {:string, "hi"},
                  "ys" => [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              ]} == v2_annotated_case.(decode_structs: false)

      assert {:ok,
              [
                cool: %{
                  "fun" => %{"cat" => {:string, "meow"}},
                  "x" => {:string, "hi"},
                  "ys" => [{{:uint, 256}, 1}, {{:uint, 256}, 2}, {{:uint, 256}, 3}]
                }
              ]} == v2_annotated_case.(decode_structs: false, named_returns: true)
    end
  end
end

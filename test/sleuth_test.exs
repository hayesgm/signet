defmodule SleuthTest do
  use ExUnit.Case
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
    end

    test "queryTwo() - annotated" do
      assert {:ok, %{"x" => {{:uint, 256}, 2}, "y" => {{:uint, 256}, 3}}} ==
               Signet.Sleuth.query_annotated(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_two(),
                 Signet.Contract.BlockNumber.query_two_selector()
               )
    end

    test "queryThree()" do
      assert {:ok, 2} ==
               Signet.Sleuth.query(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_three(),
                 Signet.Contract.BlockNumber.query_three_selector()
               )
    end

    test "queryThree() - annotated" do
      assert {:ok, {{:uint, 256}, 2}} ==
               Signet.Sleuth.query_annotated(
                 Signet.Contract.BlockNumber.bytecode(),
                 Signet.Contract.BlockNumber.encode_query_three(),
                 Signet.Contract.BlockNumber.query_three_selector()
               )
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
    end
  end
end

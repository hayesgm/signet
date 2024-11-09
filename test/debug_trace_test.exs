defmodule Signet.DebugTraceTest do
  use ExUnit.Case, async: true
  use Signet.Hex
  doctest Signet.DebugTrace
  doctest Signet.DebugTrace.StructLog
end

defmodule Signet.TypedTest do
  use ExUnit.Case, async: true
  use Signet.Hex
  doctest Signet.Typed
  doctest Signet.Typed.Domain
  doctest Signet.Typed.Type
end

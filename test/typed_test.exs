defmodule Signet.TypedTest do
  use ExUnit.Case, async: true
  doctest Signet.Typed
  doctest Signet.Typed.Domain
  doctest Signet.Typed.Type
end

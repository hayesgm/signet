defmodule Signet do
  @moduledoc """
  Signet is a library for interacting with private keys, signatures, and Etheruem.
  """

  @type address :: <<_::160>>
  @type signature :: <<_::520>>
  @type bytes32 :: <<_::256>>
end
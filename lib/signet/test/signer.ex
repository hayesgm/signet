defmodule Signet.Test.Signer do
  @moduledoc """
  A module to help with testing by setting up a simple signer with a
  unique name, to prevent name overlap in tests.
  """

  def start_signer(name \\ nil) do
    name =
      case name do
        nil ->
          String.to_atom("TestSigner#{System.unique_integer([:positive])}")

        els ->
          els
      end

    priv_key = "800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf"

    Signet.Signer.start_link(
      mfa: {Signet.Signer.Curvy, :sign, [Base.decode16!(priv_key, case: :mixed)]},
      name: name
    )

    GenServer.cast(name, :set_address)

    name
  end
end

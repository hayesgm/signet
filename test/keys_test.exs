defmodule Signet.KeysTest do
  use ExUnit.Case, async: true
  doctest Signet.Keys

  test "generate keypair" do
    {address, priv_key} = Signet.Keys.generate_keypair()
    {:ok, sig} = Signet.Signer.Curvy.sign("test", priv_key)
    {:ok, recid} = Signet.Recover.find_recid("test", sig, address)
    assert Signet.Recover.recover_eth("test", %{sig | recid: recid}) == address
  end
end

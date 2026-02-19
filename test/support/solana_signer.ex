defmodule Signet.Solana.Test.Signer do
  @moduledoc """
  Test helper for starting a Solana Ed25519 signer with a unique name.
  """

  # RFC 8032 Test 1 seed
  @test_seed Base.decode16!(
               "9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60",
               case: :upper
             )

  def test_seed, do: @test_seed

  def start_signer(name \\ nil) do
    name =
      case name do
        nil -> String.to_atom("SolTestSigner#{System.unique_integer([:positive])}")
        name -> name
      end

    {:ok, _pid} =
      Signet.Solana.Signer.start_link(
        mfa: {Signet.Solana.Signer.Ed25519, :sign, [@test_seed]},
        name: name
      )

    name
  end
end

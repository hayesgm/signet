defmodule Signet do
  @moduledoc """
  Signet is a library for interacting with private keys, signatures, and Etheruem.
  """

  @type address :: <<_::160>>
  @type signature :: <<_::520>>
  @type bytes32 :: <<_::256>>
  @type contract :: address() | atom()

  @doc ~S"""
  Returns a contract address, that may have been set in configuration.

  ## Examples

      iex> Signet.get_contract_address(<<1::160>>)
      <<1::160>>

      iex> Signet.get_contract_address("0x0000000000000000000000000000000000000001")
      <<1::160>>

      iex> Application.put_env(:signet, :contracts, [test: "0x0000000000000000000000000000000000000001"])
      iex> Signet.get_contract_address(:test)
      <<1::160>>
  """
  def get_contract_address(address) when is_binary(address),
    do: Signet.Util.decode_hex_input!(address)

  def get_contract_address(contract) when is_atom(contract) do
    Application.get_env(:signet, :contracts, [])
    |> Keyword.fetch!(contract)
    |> Signet.Util.decode_hex_input!()
  end
end

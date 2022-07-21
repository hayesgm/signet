defmodule Signet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def chain_id(), do: Signet.Util.parse_chain_id(Application.get_env(:signet, :chain_id, 1))

  def ethereum_node(),
    do: Application.get_env(:signet, :ethereum_node, "https://mainnet.infura.io")

  def http_client(), do: Application.get_env(:signet, :client, HTTPoison)

  @impl true
  def start(_type, _args) do
    signers = Application.get_env(:signet, :signer, [])

    children = Enum.map(signers, &get_signer_spec/1)

    opts = [strategy: :one_for_one, name: Signet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def get_signer_spec({name, signer_type}) do
    name = case name do
      :default ->
        Signet.Signer.Default

      els ->
        els
    end

    Supervisor.child_spec(
      {Signet.Signer, mfa: signer_mfa(signer_type), name: name},
      id: name
    )
  end

  defp signer_mfa({:priv_key, priv_key}) do
    {Signet.Signer.Curvy, :sign, [Signet.Util.decode_hex_input!(priv_key)]}
  end

  defp signer_mfa({:cloud_kms, kms_credentials, key_path, version}) do
    # E.g. "projects/*/locations/*/keyRings/*/cryptoKeys/*"

    ["projects", project, "locations", location, "keyRings", key_ring, "cryptoKeys", key_id] =
      String.split(key_path, "/")

    {Signet.Signer.CloudKMS, :sign,
     [kms_credentials, project, location, key_ring, key_id, version]}
  end
end

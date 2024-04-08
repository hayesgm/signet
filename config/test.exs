import Config

config :tesla, adapter: Tesla.Mock
config :signet, :client, Signet.Test.Client
config :signet, :open_chain_client, Signet.OpenChainTest.TestClient
config :signet, :open_chain_base_url, "https://example.com/open-chain"
config :signet, :chain_id, :goerli
config :signet, :signer, default: {:priv_key, <<1::256>>}

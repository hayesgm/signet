import Config

config :tesla, adapter: Tesla.Mock
config :signet, :client, Signet.Test.Client
config :signet, :chain_id, :goerli
config :signet, :signer, default: {:priv_key, <<1::256>>}

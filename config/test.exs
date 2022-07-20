import Config

config :tesla, adapter: Tesla.Mock
config :signet, :client, Signet.Test.Client
config :signet, :chain_id, :goerli

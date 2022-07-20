import Config

config :tesla, adapter: Tesla.Mock
config :signet, :client, SignetPoisonMock
config :signet, :chain_id, :goerli

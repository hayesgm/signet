import Config

config :signet, :client, SignetFinch

import_config "#{Mix.env()}.exs"

import Config

config :signet, :client, HTTPoison

import_config "#{Mix.env()}.exs"

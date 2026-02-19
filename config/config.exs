import Config

# Note: :client is the module that handles HTTP requests (Finch in prod, mock in test).
# The Finch *process name* is configured separately via :finch_name (defaults to SignetFinch).
# config :signet, :client, Finch  # this is the default, no need to set

import_config "#{Mix.env()}.exs"

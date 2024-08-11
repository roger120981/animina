import Config

# Note we also include the path to a cache manifest
# containing the digested version of static files. This
# manifest is generated by the `mix assets.deploy` task,
# which you should run after static files are built and
# before starting your production server.
config :animina, AniminaWeb.Endpoint,
  cache_static_manifest: "priv/static/cache_manifest.json",
  http: [ip: {0, 0, 0, 0}, port: System.get_env("PORT") || 4005],
  server: true

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Animina.Finch

# Disable Swoosh Local Memory Storage
config :swoosh,
  local: false,
  adapter: Swoosh.Adapters.SMTP,
  relay: "localhost",
  port: 25,
  domain: "animina.de"

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.

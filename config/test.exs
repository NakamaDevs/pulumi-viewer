import Config

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "bwCJhTjU8fS73NaoziiugtlcIV1iqGZVtVpF6bpcdy8"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pulumi_viewer, PulumiViewerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "JT6xHaph2NtGcpukrqkec06l/gCIQ7EHWdn3oL2lnq//ju/GNC2xvS5NueDB6Dek",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

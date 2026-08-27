import Config

config :markdow,
  ecto_repos: [Markdow.Repo],
  api_key: "development",
  agent_auth_sweeper: true,
  allowed_mcp_origins: ["http://localhost:4000", "http://127.0.0.1:4000"],
  embedding_secret_key: "0123456789abcdef0123456789abcdef",
  marketing_routes: true,
  legal: [
    operator_name: "Markdow development instance",
    operator_address: "Not a public deployment",
    contact_email: "owner@markdow.local",
    effective_date: "11 August 2026"
  ],
  rate_limits: [
    marketing: [scale_ms: 60_000, limit: 60],
    documentation: [scale_ms: 60_000, limit: 60],
    api: [scale_ms: 60_000, limit: 120],
    authentication: [scale_ms: 60_000, limit: 30],
    model_context_protocol: [scale_ms: 60_000, limit: 120]
  ],
  agent_auth: [
    registration_ttl_seconds: 86_400,
    claim_attempt_ttl_seconds: 600,
    registration_address_limit: 10,
    registration_global_limit: 100,
    claim_attempt_limit: 5,
    sign_in_attempt_limit: 10,
    assertion_ttl_seconds: 86_400,
    access_token_ttl_seconds: 3_600,
    poll_interval_seconds: 5,
    allow_ephemeral_signing_key: true
  ],
  data_dir: "~/.markdow",
  storage: [
    driver: "local",
    path: "~/.markdow/vault"
  ]

config :markdow, MarkdowWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  render_errors: [
    formats: [json: MarkdowWeb.ErrorJSON],
    layout: false
  ],
  secret_key_base: "jIFizEmNBFSgwmjACbELNhTwODxuINgDTghhJjwgMhRgGGKjKkTiTHrIhadgRZBj",
  url: [host: "localhost"]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, JSON
config :postgrex, :json_library, JSON

# Telemetry is opt-in: an instance without a configured collector exports
# nothing and never opens a connection. `config/runtime.exs` turns the exporters
# on when OTEL_EXPORTER_OTLP_ENDPOINT is present.
config :markdow, observability_enabled: false
config :opentelemetry, traces_exporter: :none

# Social cards are rendered by a pooled headless browser. browse_chrome detects
# a Chrome or Chromium binary and launches it with the container-safe flags.
# config/test.exs empties the pool so tests never launch one, and
# config/runtime.exs makes the size tunable per deployment.
config :markdow, open_graph: [enabled: true]

config :browse_chrome,
  default_pool: MarkdowWeb.OpenGraph.BrowserPool,
  pools: [{MarkdowWeb.OpenGraph.BrowserPool, [pool_size: 1]}]

config :phoenix,
       :filter_parameters,
       ~w(password token email_verification_token claim_token claim_attempt_token user_code assertion data_base64)

config :markdow, Markdow.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, Swoosh.ApiClient.Finch

# Boruta backs the RFC 7591 registration endpoint and the client credentials
# grant. It owns the oauth_clients, oauth_scopes and oauth_tokens tables and
# nothing else: the claim ceremony in Markdow.AgentAuth keeps issuing its own
# tokens, and both kinds are accepted by MarkdowWeb.ApiAuth.
config :boruta, Boruta.Oauth,
  repo: Markdow.Repo,
  contexts: [resource_owners: Markdow.OAuth.ResourceOwners],
  issuer: "https://markdow.example.com",
  max_ttl: [
    authorization_code: 60,
    # A registered client renews on its own with its own secret, so the token
    # stays short. This is what a machine peer holds instead of the one hour
    # access token the claim ceremony issues and cannot refresh.
    access_token: 3_600,
    id_token: 3_600,
    refresh_token: 60 * 60 * 24 * 30
  ]

import_config "#{config_env()}.exs"

import Config

test_root = Path.join(System.tmp_dir!(), "markdow-test-#{System.unique_integer([:positive])}")
test_port = String.to_integer(System.get_env("MARKDOW_TEST_PORT", "4002"))

config :markdow,
  api_key: "test",
  agent_auth_sweeper: false,
  embedding_secret_key: "abcdef0123456789abcdef0123456789",
  rate_limits: [
    marketing: [scale_ms: 60_000, limit: 100_000],
    documentation: [scale_ms: 60_000, limit: 100_000],
    api: [scale_ms: 60_000, limit: 100_000],
    authentication: [scale_ms: 60_000, limit: 100_000],
    model_context_protocol: [scale_ms: 60_000, limit: 100_000]
  ],
  data_dir: test_root,
  storage: [
    driver: "local",
    path: Path.join(test_root, "vault")
  ]

config :markdow, Markdow.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database:
    System.get_env(
      "MARKDOW_TEST_DATABASE_NAME",
      "markdow_test#{System.get_env("MIX_TEST_PARTITION")}"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :markdow, MarkdowWeb.Endpoint,
  url: [host: "localhost", port: test_port, scheme: "http"],
  http: [ip: {127, 0, 0, 1}, port: test_port],
  server: false

config :markdow, Markdow.Mailer, adapter: Swoosh.Adapters.Test
config :argon2_elixir, t_cost: 1, m_cost: 8
config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime

import Config

config :markdow, Markdow.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: System.get_env("MARKDOW_DATABASE_NAME", "markdow_dev"),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :logger, level: :debug

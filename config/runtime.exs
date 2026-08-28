import Config

data_dir = System.get_env("MARKDOW_DATA_DIR", "~/.markdow")
storage_path = System.get_env("MARKDOW_STORAGE_PATH", Path.join(data_dir, "vault"))

api_key =
  case {config_env(), System.get_env("MARKDOW_API_KEY")} do
    {:prod, nil} ->
      raise "environment variable MARKDOW_API_KEY is missing"

    {:prod, value} when byte_size(value) < 32 ->
      raise "MARKDOW_API_KEY must contain at least 32 bytes in production"

    {:prod, value} ->
      value

    {_environment, nil} ->
      "development"

    {_environment, value} ->
      value
  end

port =
  case config_env() do
    :test -> String.to_integer(System.get_env("MARKDOW_TEST_PORT", "4002"))
    _environment -> String.to_integer(System.get_env("MARKDOW_PORT", "4000"))
  end

marketing_routes = System.get_env("MARKDOW_MARKETING_ROUTES", "true") in ~w(true 1)
rate_limit_window = String.to_integer(System.get_env("MARKDOW_RATE_LIMIT_WINDOW_MS", "60000"))

public_host =
  case {config_env(), System.get_env("MARKDOW_HOST")} do
    {:prod, nil} -> raise "environment variable MARKDOW_HOST is missing"
    {_environment, nil} -> "localhost"
    {_environment, value} -> value
  end

public_scheme =
  System.get_env("MARKDOW_SCHEME", if(config_env() == :prod, do: "https", else: "http"))

public_port =
  String.to_integer(
    System.get_env(
      "MARKDOW_URL_PORT",
      if(public_scheme == "https", do: "443", else: Integer.to_string(port))
    )
  )

default_public_origin =
  if (public_scheme == "https" and public_port == 443) or
       (public_scheme == "http" and public_port == 80) do
    "#{public_scheme}://#{public_host}"
  else
    "#{public_scheme}://#{public_host}:#{public_port}"
  end

allowed_mcp_origins =
  System.get_env("MARKDOW_ALLOWED_MCP_ORIGINS", default_public_origin)
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))

analytics_host = System.get_env("SMOLANALYTICS_HOST")
analytics_write_key = System.get_env("SMOLANALYTICS_WRITE_KEY")

analytics_enabled =
  Enum.all?([analytics_host, analytics_write_key], fn value ->
    is_binary(value) and String.trim(value) != ""
  end)

if analytics_enabled and config_env() == :prod and URI.parse(analytics_host).scheme != "https" do
  raise "SMOLANALYTICS_HOST must use HTTPS in production"
end

# Traces, metrics, and logs all travel to the same OpenTelemetry collector. In
# the production cluster that is the shared Alloy service, which forwards to
# Tempo, Prometheus, and Loki. Without an endpoint the exporters stay off, which
# is the expected state for development and for self-hosted instances.
case System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  endpoint when is_binary(endpoint) and endpoint != "" ->
    config :markdow, observability_enabled: true
    config :opentelemetry, traces_exporter: :otlp
    config :opentelemetry_exporter, otlp_endpoint: endpoint
    config :otel_metric_exporter, otlp_endpoint: endpoint

  _endpoint ->
    config :markdow, observability_enabled: false
    config :opentelemetry, traces_exporter: :none
end

# Social cards cost a headless browser. An instance that cannot afford one, or
# does not want the marketing pages, sets the pool size to zero: no browser is
# started, the pages omit the image tags, and the endpoint reports the feature
# as unavailable.
if config_env() != :test do
  open_graph_pool_size =
    "MARKDOW_OG_BROWSER_POOL_SIZE"
    |> System.get_env("2")
    |> String.to_integer()

  open_graph_cache_dir =
    System.get_env("MARKDOW_OG_CACHE_DIR", Path.join(Path.expand(data_dir), "og"))

  if open_graph_pool_size > 0 do
    config :browse_chrome,
      default_pool: MarkdowWeb.OpenGraph.BrowserPool,
      pools: [{MarkdowWeb.OpenGraph.BrowserPool, [pool_size: open_graph_pool_size]}]

    config :markdow, open_graph: [enabled: true, cache_dir: open_graph_cache_dir]
  else
    config :browse_chrome, pools: []
    config :markdow, open_graph: [enabled: false, cache_dir: open_graph_cache_dir]
  end
end

agent_auth_private_key =
  case {config_env(), System.get_env("MARKDOW_AGENT_AUTH_PRIVATE_KEY_PEM")} do
    {:prod, nil} ->
      raise "environment variable MARKDOW_AGENT_AUTH_PRIVATE_KEY_PEM is missing"

    {_environment, value} ->
      value
  end

agent_auth_user_code_hmac_key =
  case {config_env(), System.get_env("MARKDOW_AGENT_AUTH_USER_CODE_HMAC_KEY")} do
    {:prod, nil} ->
      raise "environment variable MARKDOW_AGENT_AUTH_USER_CODE_HMAC_KEY is missing"

    {:prod, value} when byte_size(value) < 32 ->
      raise "MARKDOW_AGENT_AUTH_USER_CODE_HMAC_KEY must contain at least 32 bytes in production"

    {_environment, nil} ->
      api_key

    {_environment, value} ->
      value
  end

embedding_secret_key =
  case {config_env(), System.get_env("MARKDOW_EMBEDDING_SECRET_KEY")} do
    {:prod, nil} ->
      raise "environment variable MARKDOW_EMBEDDING_SECRET_KEY is missing"

    {_environment, nil} ->
      "0123456789abcdef0123456789abcdef"

    {_environment, encoded} ->
      case Base.decode64(encoded) do
        {:ok, key} when byte_size(key) == 32 -> key
        _invalid -> raise "MARKDOW_EMBEDDING_SECRET_KEY must be a base64-encoded 32-byte key"
      end
  end

legal =
  if config_env() == :prod and marketing_routes do
    [
      operator_name:
        System.get_env("MARKDOW_LEGAL_OPERATOR_NAME") ||
          raise("environment variable MARKDOW_LEGAL_OPERATOR_NAME is missing"),
      operator_address:
        System.get_env("MARKDOW_LEGAL_OPERATOR_ADDRESS") ||
          raise("environment variable MARKDOW_LEGAL_OPERATOR_ADDRESS is missing"),
      contact_email:
        System.get_env("MARKDOW_LEGAL_CONTACT_EMAIL") ||
          raise("environment variable MARKDOW_LEGAL_CONTACT_EMAIL is missing"),
      registration: System.get_env("MARKDOW_LEGAL_REGISTRATION"),
      tax_identifier: System.get_env("MARKDOW_LEGAL_TAX_IDENTIFIER"),
      effective_date: System.get_env("MARKDOW_LEGAL_EFFECTIVE_DATE", "11 August 2026")
    ]
  else
    [
      operator_name:
        System.get_env("MARKDOW_LEGAL_OPERATOR_NAME", "Markdow development instance"),
      operator_address:
        System.get_env("MARKDOW_LEGAL_OPERATOR_ADDRESS", "Not a public deployment"),
      contact_email: System.get_env("MARKDOW_LEGAL_CONTACT_EMAIL", "owner@markdow.local"),
      registration: System.get_env("MARKDOW_LEGAL_REGISTRATION"),
      tax_identifier: System.get_env("MARKDOW_LEGAL_TAX_IDENTIFIER"),
      effective_date: System.get_env("MARKDOW_LEGAL_EFFECTIVE_DATE", "11 August 2026")
    ]
  end

if config_env() == :prod do
  database_url =
    System.get_env("MARKDOW_DATABASE_URL") ||
      raise "environment variable MARKDOW_DATABASE_URL is missing"

  database_transport_security =
    case System.get_env("MARKDOW_DATABASE_SSL", "true") do
      value when value in ~w(false 0) ->
        false

      _value ->
        certificate_authority_file =
          System.get_env("MARKDOW_DATABASE_CERTIFICATE_AUTHORITY_FILE") ||
            raise "environment variable MARKDOW_DATABASE_CERTIFICATE_AUTHORITY_FILE is missing"

        database_host = database_url |> URI.parse() |> Map.fetch!(:host)

        [
          verify: :verify_peer,
          cacertfile: certificate_authority_file,
          server_name_indication: String.to_charlist(database_host),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
    end

  socket_options = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :markdow, Markdow.Repo,
    url: database_url,
    ssl: database_transport_security,
    pool_size: String.to_integer(System.get_env("MARKDOW_POOL_SIZE", "10")),
    socket_options: socket_options

  config :markdow, MarkdowWeb.Endpoint,
    secret_key_base:
      System.get_env("MARKDOW_SECRET_KEY_BASE") ||
        raise("environment variable MARKDOW_SECRET_KEY_BASE is missing")

  smtp_relay = System.get_env("MARKDOW_SMTP_RELAY", "smtp-relay.pepicrft.me")

  config :markdow, Markdow.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_relay,
    port: String.to_integer(System.get_env("MARKDOW_SMTP_PORT", "587")),
    auth: :never,
    tls: :always,
    tls_options: [
      versions: [:"tlsv1.2", :"tlsv1.3"],
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(smtp_relay),
      depth: 99,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ],
    retries: 2,
    no_mx_lookups: true
end

config :markdow,
  api_key: api_key,
  allowed_mcp_origins: allowed_mcp_origins,
  email_from:
    {System.get_env("MARKDOW_EMAIL_FROM_NAME", "Markdow"),
     System.get_env("MARKDOW_EMAIL_FROM_ADDRESS", "hello@markdow.org")},
  embedding_secret_key: embedding_secret_key,
  # Accounts choose their own embeddings endpoint, and anything resolving to a
  # private address is refused so the server cannot be aimed at internal
  # services. An operator names hosts that are exempt, comma separated, which is
  # how a deployment permits a gateway it runs itself.
  embeddings_allowed_hosts:
    "MARKDOW_EMBEDDINGS_ALLOWED_HOSTS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "")),
  marketing_routes: marketing_routes,
  legal: legal,
  rate_limits: [
    marketing: [
      scale_ms: rate_limit_window,
      limit: String.to_integer(System.get_env("MARKDOW_RATE_LIMIT_MARKETING", "60"))
    ],
    documentation: [
      scale_ms: rate_limit_window,
      limit: String.to_integer(System.get_env("MARKDOW_RATE_LIMIT_DOCUMENTATION", "60"))
    ],
    api: [
      scale_ms: rate_limit_window,
      limit: String.to_integer(System.get_env("MARKDOW_RATE_LIMIT_API", "120"))
    ],
    authentication: [
      scale_ms: rate_limit_window,
      limit: String.to_integer(System.get_env("MARKDOW_RATE_LIMIT_AUTHENTICATION", "30"))
    ],
    model_context_protocol: [
      scale_ms: rate_limit_window,
      limit: String.to_integer(System.get_env("MARKDOW_RATE_LIMIT_MCP", "120"))
    ]
  ],
  agent_auth: [
    registration_ttl_seconds: 86_400,
    claim_attempt_ttl_seconds: 600,
    registration_address_limit:
      String.to_integer(System.get_env("MARKDOW_AGENT_AUTH_ADDRESS_LIMIT", "10")),
    registration_global_limit:
      String.to_integer(System.get_env("MARKDOW_AGENT_AUTH_GLOBAL_LIMIT", "100")),
    claim_attempt_limit:
      String.to_integer(System.get_env("MARKDOW_AGENT_AUTH_CLAIM_ATTEMPT_LIMIT", "5")),
    sign_in_attempt_limit:
      String.to_integer(System.get_env("MARKDOW_AGENT_AUTH_SIGN_IN_ATTEMPT_LIMIT", "10")),
    assertion_ttl_seconds: 86_400,
    access_token_ttl_seconds: 3_600,
    poll_interval_seconds: 5,
    private_key_pem: agent_auth_private_key,
    user_code_hmac_key: agent_auth_user_code_hmac_key,
    allow_ephemeral_signing_key:
      System.get_env(
        "MARKDOW_AGENT_AUTH_ALLOW_EPHEMERAL_KEY",
        if(config_env() == :prod, do: "false", else: "true")
      ) in ~w(true 1)
  ],
  data_dir: data_dir,
  storage: [
    driver: System.get_env("MARKDOW_STORAGE_DRIVER", "local"),
    path: storage_path
  ]

# Tokens Boruta signs carry this as their issuer, and it has to be the origin
# clients discovered the authorization server at or they will refuse them.
config :boruta, Boruta.Oauth,
  repo: Markdow.Repo,
  contexts: [resource_owners: Markdow.OAuth.ResourceOwners],
  issuer: default_public_origin,
  max_ttl: [
    authorization_code: 60,
    access_token:
      String.to_integer(System.get_env("MARKDOW_OAUTH_ACCESS_TOKEN_TTL_SECONDS", "3600")),
    id_token: 3_600,
    refresh_token: 60 * 60 * 24 * 30
  ]

if System.get_env("MARKDOW_SERVER") in ~w(true 1) or System.get_env("PHX_SERVER") in ~w(true 1) do
  config :markdow, MarkdowWeb.Endpoint, server: true
end

config :markdow, MarkdowWeb.Endpoint,
  http: [
    ip: if(config_env() == :prod, do: {0, 0, 0, 0}, else: {127, 0, 0, 1}),
    port: port
  ],
  url: [scheme: public_scheme, host: public_host, port: public_port],
  analytics: [
    enabled: analytics_enabled,
    host: analytics_host,
    write_key: analytics_write_key
  ]

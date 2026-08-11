defmodule MarkdowWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :markdow

  @secure_cookies Application.compile_env(:markdow, :secure_cookies, false)
  @session_options [
    store: :cookie,
    key: "_markdow_session",
    signing_salt: "agent-claim",
    http_only: true,
    secure: @secure_cookies,
    same_site: "Lax"
  ]

  plug Plug.Static,
    at: "/",
    from: :markdow,
    gzip: false,
    only: ~w(assets)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: JSON

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug MarkdowWeb.Router
end

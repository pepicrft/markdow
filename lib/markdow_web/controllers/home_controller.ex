defmodule MarkdowWeb.HomeController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MarkdowWeb.HomePage
  alias OpenApiSpex.Schema

  tags ["Website"]
  security []

  plug MarkdowWeb.MarketingRoutes

  operation :show,
    operation_id: "home",
    summary: "Understand what Markdow is",
    responses: [ok: {"Editorial product introduction", "text/html", %Schema{type: :string}}]

  def show(conn, _params) do
    analytics =
      conn.private[:markdow_analytics] ||
        Application.get_env(:markdow, MarkdowWeb.Endpoint, [])
        |> Keyword.get(:analytics, [])

    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header(
      "content-security-policy",
      content_security_policy(analytics)
    )
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, HomePage.html(analytics))
  end

  defp content_security_policy(analytics) do
    analytics_source =
      case {Keyword.get(analytics, :enabled, false), Keyword.get(analytics, :host)} do
        {true, host} when is_binary(host) and host != "" -> " #{origin(host)}"
        _disabled -> ""
      end

    "default-src 'none'; script-src 'self'#{analytics_source}; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
  end

  defp origin(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port}
      when scheme in ["http", "https"] and is_binary(host) ->
        URI.to_string(%URI{scheme: scheme, host: host, port: port})

      _invalid ->
        "'none'"
    end
  end
end

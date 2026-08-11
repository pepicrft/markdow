defmodule MarkdowWeb.MarketingRoutes do
  @moduledoc false

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    enabled =
      case Map.fetch(conn.private, :markdow_marketing_routes) do
        {:ok, value} -> value
        :error -> Application.get_env(:markdow, :marketing_routes, true)
      end

    if enabled do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Not found")
      |> halt()
    end
  end
end

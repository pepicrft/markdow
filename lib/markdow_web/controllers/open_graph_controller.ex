defmodule MarkdowWeb.OpenGraphController do
  @moduledoc """
  Serves the social preview image for a marketing page.

  The image is rendered on the first request and read from the cache on every
  later one. A request without a signature minted by `MarkdowWeb.OpenGraph` is
  refused before any rendering happens.
  """

  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MarkdowWeb.OpenGraph
  alias OpenApiSpex.Schema

  tags ["Website"]
  security []

  plug MarkdowWeb.MarketingRoutes

  operation :show,
    operation_id: "open_graph_image",
    summary: "Fetch the social preview image for a marketing page",
    parameters: [
      page: [in: :query, description: "Marketing page name", type: :string, required: true],
      v: [in: :query, description: "Card version", type: :string, required: true],
      sig: [in: :query, description: "URL signature", type: :string, required: true]
    ],
    responses: [
      ok: {"Rendered social card", "image/jpeg", %Schema{type: :string, format: :binary}}
    ]

  def show(conn, params) do
    if OpenGraph.verify_signature(params) do
      serve(conn, params)
    else
      send_error(conn, :forbidden, "Invalid signature")
    end
  end

  defp serve(conn, params) do
    case OpenGraph.render(params, OpenGraph.configuration(conn)) do
      {:ok, bytes} ->
        conn
        |> put_resp_content_type("image/jpeg", nil)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_resp(200, bytes)

      {:error, :not_found} ->
        send_error(conn, :not_found, "Not found")

      {:error, :disabled} ->
        send_error(conn, :not_found, "Social cards are not enabled on this instance")

      {:error, _reason} ->
        send_error(conn, :service_unavailable, "The image could not be rendered")
    end
  end

  defp send_error(conn, status, message) do
    conn
    |> put_resp_content_type("text/plain", "utf-8")
    |> send_resp(status, message)
  end
end

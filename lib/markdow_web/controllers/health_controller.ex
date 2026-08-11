defmodule MarkdowWeb.HealthController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.Index
  alias Markdow.Operations
  alias MarkdowWeb.ApiSchemas.Status

  tags ["Service"]
  security []

  operation :show,
    operation_id: "health",
    summary: "Check service health",
    responses: [ok: {"Service is ready", "application/json", Status}]

  def show(conn, _params) do
    index = conn.private[:markdow_index] || Index.context()
    MarkdowWeb.ApiResponse.send_result(conn, Operations.call("health", %{}, index))
  end
end

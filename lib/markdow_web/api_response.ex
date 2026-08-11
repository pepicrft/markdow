defmodule MarkdowWeb.ApiResponse do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @spec send_result(Plug.Conn.t(), {:ok, term()} | {:error, term()}, non_neg_integer()) ::
          Plug.Conn.t()
  def send_result(conn, result, success_status \\ 200)

  def send_result(conn, {:ok, value}, success_status) do
    conn |> put_status(success_status) |> json(value)
  end

  def send_result(conn, {:error, :not_found}, _success_status) do
    conn |> put_status(404) |> json(%{error: "not_found"})
  end

  def send_result(conn, {:error, :embedding_not_configured}, _success_status) do
    conn |> put_status(404) |> json(%{error: "embedding_not_configured"})
  end

  def send_result(conn, {:error, :forbidden}, _success_status) do
    conn |> put_status(403) |> json(%{error: "forbidden"})
  end

  def send_result(conn, {:error, reason}, _success_status)
      when reason in [
             :invalid_arguments,
             :invalid_note,
             :invalid_path,
             :invalid_base64,
             :invalid_utf8,
             :invalid_query,
             :invalid_embedding_input,
             :embedding_provider_rejected,
             :embedding_provider_invalid_response
           ] do
    conn |> put_status(422) |> json(%{error: to_string(reason)})
  end

  def send_result(conn, {:error, :document_too_large}, _success_status) do
    conn |> put_status(413) |> json(%{error: "document_too_large"})
  end

  def send_result(conn, {:error, reason}, _success_status)
      when reason in [:embedding_provider_unavailable, :embedding_secret_key_unavailable] do
    conn |> put_status(503) |> json(%{error: to_string(reason)})
  end

  def send_result(conn, {:error, %Ecto.Changeset{}}, _success_status) do
    conn |> put_status(422) |> json(%{error: "invalid_arguments"})
  end

  def send_result(conn, {:error, _reason}, _success_status) do
    conn |> put_status(500) |> json(%{error: "operation_failed"})
  end
end

defmodule MarkdowWeb.RateLimit do
  @moduledoc false

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts) do
    Keyword.validate!(opts, [:bucket, :response])
  end

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    response = Keyword.get(opts, :response, :json)
    limits = conn.private[:markdow_rate_limits] || Application.fetch_env!(:markdow, :rate_limits)
    settings = Keyword.fetch!(limits, bucket)
    scale = Keyword.fetch!(settings, :scale_ms)
    limit = Keyword.fetch!(settings, :limit)
    limiter = conn.private[:markdow_rate_limiter] || Markdow.RateLimit

    case limiter.hit(rate_key(conn, bucket), scale, limit) do
      {:allow, count} -> allow(conn, limit, count)
      {:deny, retry_after} -> deny(conn, response, retry_after)
    end
  end

  defp allow(conn, limit, count) do
    conn
    |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
    |> put_resp_header("x-ratelimit-remaining", Integer.to_string(max(limit - count, 0)))
  end

  defp deny(conn, response, retry_after) do
    body =
      case response do
        :text -> "Too many requests"
        :json -> JSON.encode!(%{error: "rate_limit_exceeded"})
      end

    content_type = if response == :json, do: "application/json", else: "text/plain"
    retry_after_seconds = retry_after |> Kernel./(1_000) |> Float.ceil() |> trunc() |> max(1)

    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_after_seconds))
    |> put_resp_content_type(content_type)
    |> send_resp(429, body)
    |> halt()
  end

  defp rate_key(conn, bucket) do
    [bucket, request_identity(conn), conn.private[:markdow_rate_limit_namespace]]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp request_identity(conn) do
    case get_req_header(conn, "authorization") ++ get_req_header(conn, "x-api-key") do
      [credential | _credentials] -> "credential:" <> digest(credential)
      [] -> "address:" <> (conn.remote_ip |> :inet.ntoa() |> to_string())
    end
  end

  defp digest(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.url_encode64(padding: false)
  end
end

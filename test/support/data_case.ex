defmodule Markdow.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Markdow.Index
  alias Markdow.Index.Context
  alias Markdow.Repo
  alias Markdow.Storage.LocalFs

  using do
    quote do
      use Mimic
    end
  end

  setup do
    sandbox_owner = Sandbox.start_owner!(Repo, shared: false)

    root =
      Path.join(
        System.tmp_dir!(),
        "markdow-case-#{System.unique_integer([:positive, :monotonic])}"
      )

    storage_spec =
      Supervisor.child_spec(
        {LocalFs, path: Path.join(root, "vault"), name: nil},
        id: {:storage, System.unique_integer([:positive])}
      )

    {:ok, storage} = start_supervised(storage_spec)
    index = Index.context(repo: Repo, storage: {LocalFs, storage})

    on_exit(fn ->
      Sandbox.stop_owner(sandbox_owner)
      File.rm_rf(root)
    end)

    {:ok, index: index, root: root, storage: storage}
  end

  @spec endpoint_conn(
          atom(),
          String.t(),
          term(),
          Context.t(),
          String.t() | nil,
          String.t(),
          keyword()
        ) ::
          Plug.Conn.t()
  def endpoint_conn(
        method,
        path,
        body,
        index,
        authorization \\ nil,
        api_key \\ "test",
        rate_limits \\ unrestricted_rate_limits()
      ) do
    conn =
      case body do
        nil ->
          Plug.Test.conn(method, path)

        body when is_binary(body) ->
          Plug.Test.conn(method, path, body)

        body ->
          Plug.Test.conn(method, path, JSON.encode!(body))
      end

    conn
    |> Plug.Conn.put_private(:markdow_index, index)
    |> Plug.Conn.put_private(:markdow_api_key, api_key)
    |> Plug.Conn.put_private(:markdow_rate_limit_namespace, rate_limit_namespace(index))
    |> Plug.Conn.put_private(:markdow_rate_limits, rate_limits)
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> maybe_json_content_type(body)
    |> maybe_authorize(authorization)
    |> MarkdowWeb.Endpoint.call([])
  end

  @spec form_conn(String.t(), map(), Context.t(), String.t()) :: Plug.Conn.t()
  def form_conn(path, params, index, api_key \\ "test") do
    :post
    |> Plug.Test.conn(path, URI.encode_query(params))
    |> Plug.Conn.put_private(:markdow_index, index)
    |> Plug.Conn.put_private(:markdow_api_key, api_key)
    |> Plug.Conn.put_private(:markdow_rate_limit_namespace, rate_limit_namespace(index))
    |> Plug.Conn.put_private(:markdow_rate_limits, unrestricted_rate_limits())
    |> Plug.Conn.put_req_header("accept", "application/json")
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> MarkdowWeb.Endpoint.call([])
  end

  @spec browser_conn(atom(), String.t(), map() | nil, Context.t(), map()) :: Plug.Conn.t()
  def browser_conn(method, path, params, index, session \\ %{}) do
    conn =
      case {method, params} do
        {:get, _params} -> Plug.Test.conn(:get, path)
        {_method, nil} -> Plug.Test.conn(method, path)
        {_method, values} -> Plug.Test.conn(method, path, URI.encode_query(values))
      end

    conn
    |> Plug.Conn.put_private(:markdow_index, index)
    |> Plug.Conn.put_private(:markdow_api_key, "test")
    |> Plug.Conn.put_private(:markdow_rate_limit_namespace, rate_limit_namespace(index))
    |> Plug.Conn.put_private(:markdow_rate_limits, unrestricted_rate_limits())
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
    |> Plug.Test.init_test_session(session)
    |> Plug.Conn.put_req_header("accept", "text/html")
    |> maybe_form_content_type(method)
    |> MarkdowWeb.Endpoint.call([])
  end

  @spec public_origin() :: String.t()
  def public_origin, do: MarkdowWeb.Endpoint.url()

  defp maybe_json_content_type(conn, nil), do: conn

  defp maybe_json_content_type(conn, _body),
    do: Plug.Conn.put_req_header(conn, "content-type", "application/json")

  defp maybe_authorize(conn, nil), do: conn

  defp maybe_authorize(conn, api_key),
    do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{api_key}")

  defp maybe_form_content_type(conn, :get), do: conn

  defp maybe_form_content_type(conn, _method),
    do: Plug.Conn.put_req_header(conn, "content-type", "application/x-www-form-urlencoded")

  defp rate_limit_namespace(index), do: inspect(index.storage)

  defp unrestricted_rate_limits do
    [
      marketing: [scale_ms: 60_000, limit: 100_000],
      documentation: [scale_ms: 60_000, limit: 100_000],
      api: [scale_ms: 60_000, limit: 100_000],
      authentication: [scale_ms: 60_000, limit: 100_000],
      model_context_protocol: [scale_ms: 60_000, limit: 100_000]
    ]
  end
end

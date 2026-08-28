defmodule MarkdowWeb.UserAuth do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn

  alias Markdow.Accounts
  alias Markdow.Index

  @user_session_key :markdow_user_id
  @return_to_session_key :markdow_user_return_to

  @spec init(:fetch_current_user) :: :fetch_current_user
  def init(:fetch_current_user), do: :fetch_current_user

  @spec call(Plug.Conn.t(), :fetch_current_user) :: Plug.Conn.t()
  def call(conn, :fetch_current_user), do: fetch_current_user(conn, [])

  @spec fetch_current_user(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def fetch_current_user(conn, _opts) do
    case get_session(conn, @user_session_key) do
      user_id when is_binary(user_id) ->
        case Accounts.get_user(user_id, index(conn).repo) do
          {:ok, user} -> assign(conn, :current_user, user)
          {:error, :not_found} -> assign(conn, :current_user, nil)
        end

      _missing ->
        assign(conn, :current_user, nil)
    end
  end

  @spec log_in_user(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def log_in_user(conn, %{id: user_id}) when is_binary(user_id) do
    return_to = get_session(conn, @return_to_session_key)

    conn
    |> renew_session()
    |> put_session(@user_session_key, user_id)
    |> redirect(to: return_to || "/")
  end

  @spec log_out_user(Plug.Conn.t()) :: Plug.Conn.t()
  def log_out_user(conn) do
    log_out_user(conn, "/")
  end

  @spec log_out_user(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def log_out_user(conn, return_to) when is_binary(return_to) do
    conn
    |> renew_session()
    |> redirect(to: return_to)
  end

  @spec store_return_to(Plug.Conn.t()) :: Plug.Conn.t()
  def store_return_to(%{method: "GET"} = conn),
    do: put_session(conn, @return_to_session_key, current_path(conn))

  def store_return_to(conn), do: conn

  defp renew_session(conn) do
    delete_csrf_token()
    conn |> configure_session(renew: true) |> clear_session()
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end

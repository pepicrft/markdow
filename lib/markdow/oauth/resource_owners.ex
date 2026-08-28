defmodule Markdow.OAuth.ResourceOwners do
  @moduledoc false

  @behaviour Boruta.Oauth.ResourceOwners

  import Ecto.Query

  alias Boruta.Ecto.Scope
  alias Boruta.Oauth.ResourceOwner
  alias Markdow.Accounts.User
  alias Markdow.Repo

  @impl true
  def get_by(username: username) when is_binary(username),
    do: resource_owner(Repo.get_by(User, email: normalize_email(username)))

  def get_by(sub: sub) when is_binary(sub), do: resource_owner(Repo.get(User, sub))
  def get_by(_params), do: {:error, "Account not found."}

  @impl true
  def check_password(%ResourceOwner{}, _password),
    do: {:error, "Markdow uses one-time email links for browser authentication."}

  @impl true
  def authorized_scopes(%ResourceOwner{}),
    do: Repo.all(from(scope in Scope, order_by: [asc: scope.name]))

  @impl true
  def claims(%ResourceOwner{username: email}, _scope), do: %{email: email}

  defp resource_owner(%User{id: id, email: email}),
    do: {:ok, %ResourceOwner{sub: id, username: email}}

  defp resource_owner(nil), do: {:error, "Account not found."}
  defp normalize_email(email), do: email |> String.trim() |> String.downcase()
end

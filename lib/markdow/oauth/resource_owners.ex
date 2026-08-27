defmodule Markdow.OAuth.ResourceOwners do
  @moduledoc """
  Boruta's resource owner context, backed by Markdow accounts.

  This answers for the authorization code flow, where a person signs in and
  approves a client. It deliberately refuses `check_password/2`: the password
  grant would let a client collect somebody's password and exchange it directly,
  and Markdow never offers a flow where a client sees a password. Signing in
  happens on a Markdow page, and only the code that page hands back is worth
  anything.
  """

  @behaviour Boruta.Oauth.ResourceOwners

  alias Boruta.Oauth.ResourceOwner
  alias Markdow.Accounts
  alias Markdow.Index
  alias Markdow.OAuth

  @impl Boruta.Oauth.ResourceOwners
  def get_by(sub: sub) when is_binary(sub) do
    case Accounts.get_user(sub, repo()) do
      {:ok, user} -> {:ok, %ResourceOwner{sub: user.id, username: user.email}}
      {:error, _reason} -> {:error, "Account not found."}
    end
  end

  def get_by(username: username) when is_binary(username) do
    case Accounts.get_user_by_email(username, repo()) do
      {:ok, user} -> {:ok, %ResourceOwner{sub: user.id, username: user.email}}
      {:error, _reason} -> {:error, "Account not found."}
    end
  end

  def get_by(_params), do: {:error, "Account not found."}

  @impl Boruta.Oauth.ResourceOwners
  def check_password(_resource_owner, _password),
    do: {:error, "Markdow does not exchange passwords for tokens."}

  # The ceiling a person can hand to a client is the same one an agent gets,
  # which excludes `users:write`. Approving a connection must not become a way
  # to create accounts.
  @impl Boruta.Oauth.ResourceOwners
  def authorized_scopes(%ResourceOwner{}),
    do: Enum.map(OAuth.scopes(), &%Boruta.Oauth.Scope{name: &1})

  def authorized_scopes(_resource_owner), do: []

  defp repo, do: Index.context().repo
end

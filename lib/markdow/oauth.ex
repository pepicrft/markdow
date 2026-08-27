defmodule Markdow.OAuth do
  @moduledoc """
  Dynamic client registration and the client credentials grant, backed by Boruta.

  This exists next to `Markdow.AgentAuth` rather than replacing it, because the
  two answer different questions. The claim ceremony proves a person is present
  and hands back a token that cannot be renewed, which is right for an agent
  acting on someone's behalf for the length of a task. A machine peer that has
  to keep working needs a credential it can present again tomorrow, and that is
  what a registered client with a secret is.

  A registered client is bound to exactly one Markdow account at registration
  time, recorded in `Markdow.OAuth.ClientOwner`. That binding is the whole of
  its authority: `Markdow.Operations.authorize_arguments/4` compares the account
  on the token against the account owning the vault, so a client can only ever
  reach the vaults of the account that registered it. A client with no binding
  can still be issued a token and will be refused by every user and vault scoped
  operation, which is the safe direction for the failure to point.
  """

  import Ecto.Query, only: [from: 2]

  alias Boruta.Ecto.Admin
  alias Boruta.Oauth.Authorization.AccessToken
  alias Boruta.Oauth.Token
  alias Markdow.AgentAuth
  alias Markdow.OAuth.ClientOwner
  alias Markdow.Repo

  @client_credentials "client_credentials"

  @spec grant_types() :: [String.t()]
  def grant_types, do: [@client_credentials]

  @doc """
  Scopes a registered client may hold.

  Deliberately the same list the claim ceremony grants, which excludes
  `users:write`: registering a client must not become a way to create accounts.
  """
  @spec scopes() :: [String.t()]
  def scopes, do: AgentAuth.agent_scopes()

  @doc """
  Makes Markdow's scopes known to Boruta as public scopes.

  Boruta resolves a requested scope against the public set for clients that do
  not carry an explicit scope association, so a scope absent from `oauth_scopes`
  is silently dropped from an issued token rather than refused. Seeding is
  idempotent and safe to call on every registration.
  """
  @spec ensure_scopes() :: :ok
  def ensure_scopes do
    existing = Admin.list_scopes() |> Enum.map(& &1.name) |> MapSet.new()

    Enum.each(scopes(), fn name ->
      unless MapSet.member?(existing, name) do
        # A racing registration may have inserted it between the read and here.
        # The unique index on name is what actually guarantees one row.
        Admin.create_scope(%{name: name, public: true, label: name})
      end
    end)

    :ok
  end

  @doc """
  Restricts a freshly registered client and binds it to an account.

  Boruta's registration changeset accepts only the RFC 7591 attributes, so the
  client arrives supporting `authorization_code` as well and belonging to
  nobody. Markdow exposes no authorization endpoint, so that grant is
  unreachable, but advertising a grant this server cannot honour would be a lie
  told to every client that reads the registration response.

  The narrowing and the binding happen together. If either fails the client is
  deleted, because a client that exists without an owner is a credential nobody
  can account for.
  """
  @spec finalize_registration(struct(), String.t()) ::
          {:ok, struct()} | {:error, term()}
  def finalize_registration(%{id: client_id}, user_id) when is_binary(user_id) do
    result =
      Repo.transaction(fn ->
        with client <- Admin.get_client!(client_id),
             {:ok, client} <-
               Admin.update_client(client, %{
                 supported_grant_types: grant_types(),
                 confidential: true
               }),
             {:ok, _owner} <-
               %ClientOwner{}
               |> ClientOwner.changeset(%{client_id: client_id, user_id: user_id})
               |> Repo.insert() do
          client
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, client} -> {:ok, client}
      {:error, reason} -> discard_client(client_id, reason)
    end
  end

  @doc """
  Resolves a Boruta access token into the authorization map Markdow operates on.

  Returns the same shape `Markdow.AgentAuth` produces for a claimed access
  token, so `Markdow.Operations` and `Markdow.MCP` cannot tell the two apart and
  neither needs a second authorization path.
  """
  @spec authorize(String.t(), [String.t()]) :: {:ok, map()} | {:error, atom()}
  def authorize(token, required_scopes) when is_binary(token) and is_list(required_scopes) do
    with {:ok, %{scope: scope, client: %{id: client_id}}} <-
           token_for(token),
         :ok <- authorize_scopes(scope, required_scopes),
         {:ok, user_id} <- owner(client_id) do
      {:ok,
       %{
         kind: :access_token,
         user_id: user_id,
         scopes: scope,
         client_id: client_id
       }}
    end
  end

  def authorize(_token, _required_scopes), do: {:error, :invalid_token}

  @doc "The account a registered client acts for, if it has one."
  @spec owner(String.t()) :: {:ok, String.t()} | {:error, :invalid_token}
  def owner(client_id) when is_binary(client_id) do
    case Repo.one(from(o in ClientOwner, where: o.client_id == ^client_id, select: o.user_id)) do
      nil -> {:error, :invalid_token}
      user_id -> {:ok, user_id}
    end
  end

  defp token_for(token) do
    case AccessToken.authorize(value: token) do
      {:ok, %Token{client: %{id: _id}} = boruta_token} -> {:ok, boruta_token}
      _error -> {:error, :invalid_token}
    end
  end

  defp authorize_scopes(granted, required) do
    granted = granted |> to_string() |> String.split() |> MapSet.new()

    if Enum.all?(required, &MapSet.member?(granted, &1)),
      do: :ok,
      else: {:error, :insufficient_scope}
  end

  defp discard_client(client_id, reason) do
    Admin.delete_client(Admin.get_client!(client_id))
    {:error, reason}
  rescue
    # The client is already gone, which is the state we wanted anyway.
    Ecto.NoResultsError -> {:error, reason}
  end
end

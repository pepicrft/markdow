defmodule Markdow.OAuth.Clients do
  @moduledoc false

  @behaviour Boruta.Oauth.Clients
  @behaviour Boruta.Openid.Clients

  import Boruta.Config, only: [repo: 0]

  alias Boruta.Ecto.Client
  alias Boruta.Ecto.Clients, as: EctoClients
  alias Boruta.Ecto.ClientStore
  alias Boruta.Ecto.OauthMapper

  @impl Boruta.Oauth.Clients
  defdelegate get_client(id), to: EctoClients

  @impl Boruta.Oauth.Clients
  defdelegate authorized_scopes(client), to: EctoClients

  @impl Boruta.Oauth.Clients
  defdelegate list_clients_jwk(), to: EctoClients

  @impl Boruta.Openid.Clients
  def create_client(params) do
    with {:ok, client} <-
           %Client{}
           |> Client.create_changeset(params)
           |> repo().insert(log: false) do
      client
      |> OauthMapper.to_oauth_schema()
      |> ClientStore.put()
    end
  end

  @impl Boruta.Openid.Clients
  defdelegate refresh_jwk_from_jwks_uri(client_id), to: EctoClients
end

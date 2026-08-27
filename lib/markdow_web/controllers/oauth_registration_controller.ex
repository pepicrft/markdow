defmodule MarkdowWeb.OAuthRegistrationController do
  @moduledoc """
  RFC 7591 dynamic client registration.

  The endpoint is protected, which RFC 7591 section 3 allows and which Markdow
  needs: a client is registered *for an account*, and an open endpoint would be
  a way to mint credentials against a vault without the person who owns it ever
  being asked. The credential presented here decides the account the new client
  will act for, and that binding cannot be changed afterwards.
  """

  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  @behaviour Boruta.Openid.DynamicRegistrationApplication

  alias Markdow.Accounts
  alias Markdow.Index
  alias Markdow.OAuth
  alias MarkdowWeb.PublicOrigin
  alias OpenApiSpex.Schema

  # Only the metadata Boruta understands, and deliberately not `jwks_uri`:
  # Boruta fetches that URL over HTTP while registering, which would turn an
  # authenticated registration into a request forgery primitive pointed at
  # anything the cluster can reach. Markdow authenticates clients by secret, so
  # nothing is lost by refusing to take a URL here.
  #
  # Boruta reads registration metadata by atom key. The mapping is spelled out
  # rather than converted, so no request can reach an atom this list does not
  # already name.
  @registration_attributes %{
    "client_name" => :client_name,
    "redirect_uris" => :redirect_uris,
    "token_endpoint_auth_method" => :token_endpoint_auth_method,
    "logo_uri" => :logo_uri
  }

  plug MarkdowWeb.ApiAuth, scopes: []

  tags ["Agent authentication"]
  security [%{"bearerAuth" => []}]

  operation :create,
    operation_id: "register_oauth_client",
    summary: "Register an OAuth client for the authenticated account",
    request_body:
      {"Client metadata", "application/json",
       %Schema{
         type: :object,
         properties: %{
           client_name: %Schema{type: :string},
           redirect_uris: %Schema{type: :array, items: %Schema{type: :string}},
           token_endpoint_auth_method: %Schema{type: :string},
           logo_uri: %Schema{type: :string},
           markdow_user_id: %Schema{
             type: :string,
             description:
               "Account the client acts for. Required when registering with an application key, ignored otherwise."
           }
         }
       }},
    responses: [
      created: {"Registered client", "application/json", %Schema{type: :object}}
    ]

  def create(conn, params) do
    case owner_id(conn, params) do
      {:ok, user_id} ->
        :ok = OAuth.ensure_scopes()

        conn
        |> Plug.Conn.put_private(:markdow_registration_user_id, user_id)
        |> Boruta.Openid.register_client(registration_attributes(params), __MODULE__)

      {:error, reason} ->
        registration_error(conn, reason)
    end
  end

  @impl Boruta.Openid.DynamicRegistrationApplication
  def client_registered(conn, client) do
    user_id = conn.private[:markdow_registration_user_id]

    case OAuth.finalize_registration(client, user_id) do
      {:ok, client} ->
        conn
        |> no_store()
        |> put_status(201)
        |> json(registration_response(conn, client))

      {:error, _reason} ->
        registration_error(conn, :registration_failed)
    end
  end

  @impl Boruta.Openid.DynamicRegistrationApplication
  def registration_failure(conn, %Ecto.Changeset{} = changeset) do
    conn
    |> put_status(400)
    |> json(%{
      error: "invalid_client_metadata",
      error_description: changeset_message(changeset)
    })
  end

  def registration_failure(conn, _reason), do: registration_error(conn, :registration_failed)

  # An agent access token already stands for one account and that account wins,
  # so a client cannot register itself against somebody else by asking. The
  # application key stands for the deployment rather than a person, so it has to
  # name the account explicitly and the account has to exist.
  #
  # A registered client cannot register further clients even for its own
  # account. It would not gain any reach it does not already have, but it would
  # let one leaked secret grow into a set of credentials that outlive revoking
  # the one that leaked. Registration stays with credentials a person holds.
  defp owner_id(conn, _params) do
    case conn.assigns.authorization do
      %{client_id: client_id} when is_binary(client_id) -> {:error, :client_may_not_register}
      %{kind: :access_token, user_id: user_id} when is_binary(user_id) -> {:ok, user_id}
      %{kind: :api_key} -> named_owner(conn)
      _other -> {:error, :owner_required}
    end
  end

  defp named_owner(conn) do
    case conn.body_params["markdow_user_id"] do
      user_id when is_binary(user_id) and user_id != "" ->
        case Accounts.get_user(user_id, index(conn).repo) do
          {:ok, _user} -> {:ok, user_id}
          {:error, _reason} -> {:error, :unknown_account}
        end

      _missing ->
        {:error, :owner_required}
    end
  end

  defp registration_attributes(params) do
    Enum.reduce(@registration_attributes, %{}, fn {name, key}, attributes ->
      case Map.fetch(params, name) do
        {:ok, value} -> Map.put(attributes, key, value)
        :error -> attributes
      end
    end)
  end

  # RFC 7591 section 3.2.1 asks for the metadata as it was actually registered,
  # not as it was asked for. Reporting an authentication method the client was
  # not given would send it to the token endpoint to fail.
  defp registration_response(conn, client) do
    origin = PublicOrigin.from_conn(conn)

    %{
      client_id: client.id,
      client_secret: client.secret,
      client_id_issued_at: DateTime.to_unix(DateTime.utc_now()),
      # Nothing expires the secret. It is revoked by deleting the client.
      client_secret_expires_at: 0,
      client_name: client.name,
      redirect_uris: client.redirect_uris,
      logo_uri: client.logo_uri,
      grant_types: client.supported_grant_types,
      token_endpoint_auth_method: hd(client.token_endpoint_auth_methods),
      token_endpoint_auth_methods: client.token_endpoint_auth_methods,
      token_endpoint: origin <> "/oauth2/token",
      scope: Enum.join(OAuth.scopes(), " ")
    }
  end

  # RFC 6749 section 5.1: a response carrying a credential must not be cached.
  defp no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end

  defp registration_error(conn, :unknown_account) do
    conn
    |> put_status(400)
    |> json(%{
      error: "invalid_client_metadata",
      error_description: "The named account does not exist."
    })
  end

  defp registration_error(conn, :client_may_not_register) do
    conn
    |> put_status(403)
    |> json(%{
      error: "invalid_client_metadata",
      error_description: "A registered client cannot register further clients."
    })
  end

  defp registration_error(conn, :owner_required) do
    conn
    |> put_status(400)
    |> json(%{
      error: "invalid_client_metadata",
      error_description:
        "Registering with an application key requires markdow_user_id naming the account the client acts for."
    })
  end

  defp registration_error(conn, _reason) do
    conn
    |> put_status(500)
    |> json(%{
      error: "invalid_client_metadata",
      error_description: "The client could not be registered."
    })
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{field} #{Enum.join(List.wrap(messages), " ")}"
    end)
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end

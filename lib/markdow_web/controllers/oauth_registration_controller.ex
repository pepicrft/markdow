defmodule MarkdowWeb.OAuthRegistrationController do
  @moduledoc false

  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  @behaviour Boruta.Openid.DynamicRegistrationApplication

  import Ecto.Changeset, only: [traverse_errors: 2]

  alias Boruta.Oauth.Client
  alias Markdow.OAuth
  alias OpenApiSpex.Schema

  @default_grant_types ["authorization_code", "refresh_token"]
  @default_response_types ["code"]
  @interactive_grant_types ["authorization_code", "refresh_token"]
  @public_auth_method "none"
  @registration_metadata_keys ~w(client_uri contacts policy_uri scope software_id software_version tos_uri)

  tags ["Authentication"]
  security []

  operation :create,
    operation_id: "register_oauth_client",
    summary: "Register a public OAuth client",
    request_body:
      {"Client metadata", "application/json",
       %Schema{
         type: :object,
         properties: %{
           client_name: %Schema{type: :string},
           redirect_uris: %Schema{type: :array, items: %Schema{type: :string}},
           grant_types: %Schema{type: :array, items: %Schema{type: :string}},
           response_types: %Schema{type: :array, items: %Schema{type: :string}},
           token_endpoint_auth_method: %Schema{type: :string}
         },
         required: [:redirect_uris]
       }},
    responses: [created: {"Registered client", "application/json", %Schema{type: :object}}]

  def create(conn, params) do
    :ok = OAuth.ensure_scopes()

    Boruta.Openid.register_client(
      conn,
      normalize(params),
      __MODULE__
    )
  end

  @impl true
  def client_registered(conn, %Client{} = client) do
    conn
    |> no_store()
    |> put_status(:created)
    |> json(%{
      client_id: client.id,
      client_id_issued_at: DateTime.utc_now() |> DateTime.to_unix(),
      client_name: client.name,
      redirect_uris: client.redirect_uris,
      grant_types: registered_grant_types(client),
      response_types: response_types(client),
      token_endpoint_auth_method: auth_method(client)
    })
  end

  @impl true
  def registration_failure(conn, changeset) do
    errors =
      changeset
      |> traverse_errors(fn {message, _options} -> message end)
      |> Enum.map_join(" ", fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)

    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_client_metadata", error_description: errors})
  end

  defp normalize(params) do
    response_types = requested_response_types(params)
    grant_types = grant_types(params)
    auth_method = @public_auth_method

    %{
      name: Map.get(params, "client_name") || Map.get(params, "name") || "Markdow client",
      redirect_uris: Map.get(params, "redirect_uris", []),
      supported_grant_types: grant_types ++ ["revoke"],
      authorized_scopes: Enum.map(OAuth.scopes(), &%{name: &1, public: true}),
      response_types: response_types,
      token_endpoint_auth_methods: [],
      confidential: false,
      pkce: true,
      public_refresh_token: true,
      public_revoke: true,
      metadata: registration_metadata(params, grant_types, response_types, auth_method)
    }
  end

  defp grant_types(params) do
    case Map.get(params, "grant_types", @default_grant_types) do
      grant_types when is_list(grant_types) ->
        supported = Enum.filter(grant_types, &(&1 in @interactive_grant_types))
        if supported == [], do: @default_grant_types, else: supported

      _invalid ->
        @default_grant_types
    end
  end

  defp requested_response_types(params) do
    case Map.get(params, "response_types", @default_response_types) do
      response_types when is_list(response_types) ->
        supported = Enum.filter(response_types, &(&1 in @default_response_types))
        if supported == [], do: @default_response_types, else: supported

      _invalid ->
        @default_response_types
    end
  end

  defp registration_metadata(params, grant_types, response_types, auth_method) do
    metadata = if is_map(params["metadata"]), do: params["metadata"], else: %{}

    params
    |> Map.take(@registration_metadata_keys)
    |> Map.merge(metadata)
    |> Map.put("grant_types", grant_types)
    |> Map.put("response_types", response_types)
    |> Map.put("token_endpoint_auth_method", auth_method)
  end

  defp auth_method(%Client{metadata: %{"token_endpoint_auth_method" => method}}), do: method
  defp auth_method(_client), do: @public_auth_method

  defp registered_grant_types(%Client{metadata: %{"grant_types" => grant_types}}), do: grant_types
  defp registered_grant_types(_client), do: @default_grant_types

  defp response_types(%Client{metadata: %{"response_types" => response_types}}),
    do: response_types

  defp response_types(_client), do: @default_response_types

  defp no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end
end

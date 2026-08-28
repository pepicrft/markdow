defmodule MarkdowWeb.DiscoveryController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.AgentAuth
  alias Markdow.OAuth
  alias MarkdowWeb.PublicOrigin
  alias OpenApiSpex.Schema

  tags ["Agent authentication"]
  security []

  operation :protected_resource,
    operation_id: "get_oauth_protected_resource",
    summary: "Discover authorization for the note interface",
    responses: [ok: {"Protected resource metadata", "application/json", %Schema{type: :object}}]

  operation :mcp_protected_resource,
    operation_id: "get_mcp_protected_resource",
    summary: "Discover authorization for the Model Context Protocol server",
    responses: [ok: {"Protected resource metadata", "application/json", %Schema{type: :object}}]

  operation :authorization_server,
    operation_id: "get_oauth_authorization_server",
    summary: "Discover OAuth authorization endpoints",
    responses: [ok: {"Authorization server metadata", "application/json", %Schema{type: :object}}]

  operation :jwks,
    operation_id: "get_agent_auth_signing_keys",
    summary: "Read public keys for legacy service identity assertions",
    responses: [ok: {"Public signing keys", "application/json", %Schema{type: :object}}]

  operation :mcp_server_card,
    operation_id: "get_mcp_server_card",
    summary: "Discover the Markdow Model Context Protocol server",
    responses: [ok: {"Server card", "application/json", %Schema{type: :object}}]

  operation :event_notify,
    operation_id: "receive_agent_security_event",
    summary: "Receive a provider security event when that optional flow is enabled",
    request_body: {"Security event", "application/secevent+jwt", %Schema{type: :string}},
    responses: [
      bad_request: {"Events are not enabled", "application/json", %Schema{type: :object}}
    ]

  def protected_resource(conn, _params),
    do: json(conn, protected_resource_document(PublicOrigin.from_conn(conn)))

  def mcp_protected_resource(conn, _params) do
    origin = PublicOrigin.from_conn(conn)

    json(conn, %{
      resource: origin <> "/mcp",
      resource_name: "Markdow Model Context Protocol server",
      authorization_servers: [origin],
      scopes_supported: OAuth.scopes(),
      bearer_methods_supported: ["header"],
      resource_documentation: origin <> "/auth.md"
    })
  end

  def authorization_server(conn, _params) do
    origin = PublicOrigin.from_conn(conn)

    json(conn, %{
      resource: origin,
      authorization_servers: [origin],
      scopes_supported: OAuth.scopes(),
      bearer_methods_supported: ["header"],
      issuer: origin,
      authorization_endpoint: origin <> "/oauth2/authorize",
      token_endpoint: origin <> "/oauth2/token",
      revocation_endpoint: origin <> "/oauth2/revoke",
      registration_endpoint: origin <> "/oauth2/register",
      grant_types_supported:
        [AgentAuth.claim_grant(), AgentAuth.jwt_bearer_grant()] ++ OAuth.grant_types(),
      response_types_supported: ["code"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      jwks_uri: origin <> "/.well-known/jwks.json",
      agent_auth: %{
        skill: origin <> "/auth.md",
        identity_endpoint: origin <> "/agent/identity",
        claim_endpoint: origin <> "/agent/identity/claim",
        events_endpoint: origin <> "/agent/event/notify",
        identity_types_supported: ["service_auth"],
        identity_assertion: %{assertion_types_supported: []},
        events_supported: []
      }
    })
  end

  def jwks(conn, _params) do
    case AgentAuth.jwks() do
      {:ok, keys} -> json(conn, keys)
      {:error, _reason} -> conn |> put_status(503) |> json(%{error: "signing_key_unavailable"})
    end
  end

  def mcp_server_card(conn, _params) do
    origin = PublicOrigin.from_conn(conn)

    json(conn, %{
      name: "Markdow",
      description:
        "Manage users, isolated Markdown vaults, notes, and bring-your-own embeddings.",
      version: "0.1.0",
      transport: %{
        type: "streamable-http",
        url: origin <> "/mcp",
        protocol_versions: ["2025-06-18", "2025-03-26"]
      },
      authentication: %{
        type: "oauth2",
        protected_resource_metadata: origin <> "/.well-known/oauth-protected-resource/mcp",
        agent_registration: origin <> "/auth.md"
      }
    })
  end

  def event_notify(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{err: "unsupported_event", description: "No events are advertised."})
  end

  defp protected_resource_document(origin) do
    %{
      resource: origin,
      resource_name: "Markdow note interface",
      authorization_servers: [origin],
      scopes_supported: OAuth.scopes(),
      bearer_methods_supported: ["header"],
      resource_documentation: origin <> "/auth.md"
    }
  end
end

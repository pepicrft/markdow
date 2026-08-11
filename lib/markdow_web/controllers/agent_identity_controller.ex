defmodule MarkdowWeb.AgentIdentityController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.AgentAuth
  alias Markdow.Index
  alias MarkdowWeb.PublicOrigin
  alias OpenApiSpex.Schema

  tags ["Agent authentication"]
  security []

  operation :create,
    operation_id: "register_agent_identity",
    summary: "Start an auth.md agent registration",
    request_body:
      {"Agent registration", "application/json",
       %Schema{
         type: :object,
         properties: %{
           type: %Schema{type: :string, enum: ["service_auth"]},
           login_hint: %Schema{type: :string, format: :email}
         },
         required: [:type, :login_hint]
       }},
    responses: [ok: {"Registration ceremony", "application/json", %Schema{type: :object}}]

  operation :claim,
    operation_id: "start_agent_claim",
    summary: "Start an anonymous claim when that optional flow is enabled",
    request_body:
      {"Claim request", "application/json", %Schema{type: :object, additionalProperties: true}},
    responses: [bad_request: {"Flow is disabled", "application/json", %Schema{type: :object}}]

  def create(conn, %{"type" => "service_auth", "login_hint" => email}) do
    opts = auth_opts(conn)

    case AgentAuth.create_service_registration(email, opts) do
      {:ok, result} -> json(conn, registration_response(result, opts))
      {:error, reason} -> registration_error(conn, reason)
    end
  end

  def create(conn, %{"type" => type}) when type in ["anonymous", "identity_assertion"] do
    conn |> put_status(400) |> json(%{error: "#{type}_not_enabled"})
  end

  def create(conn, _params), do: conn |> put_status(400) |> json(%{error: "invalid_request"})

  def claim(conn, _params) do
    conn |> put_status(400) |> json(%{error: "anonymous_not_enabled"})
  end

  defp registration_response(result, opts) do
    registration = result.registration
    origin = Keyword.fetch!(opts, :issuer)
    expires_in = max(registration.claim_attempt_expires_at - System.system_time(:second), 0)

    %{
      registration_id: registration.id,
      registration_type: registration.registration_type,
      claim_url: origin <> "/agent/identity/claim",
      claim_token: result.claim_token,
      claim_token_expires: iso8601(registration.expires_at),
      post_claim_scopes: AgentAuth.agent_scopes(),
      claim: %{
        user_code: result.user_code,
        expires_in: expires_in,
        verification_uri:
          origin <>
            "/agent/identity/claim?claim_attempt_token=" <>
            URI.encode_www_form(result.claim_attempt_token),
        interval: AgentAuth.poll_interval(opts)
      }
    }
  end

  defp registration_error(conn, reason) do
    status = if reason == :rate_limited, do: 429, else: 400
    conn |> put_status(status) |> json(%{error: to_string(reason)})
  end

  defp iso8601(unix_time) do
    case DateTime.from_unix(unix_time) do
      {:ok, date_time} -> DateTime.to_iso8601(date_time)
      {:error, _reason} -> nil
    end
  end

  defp auth_opts(conn) do
    [
      index: conn.private[:markdow_index] || Index.context(),
      issuer: PublicOrigin.from_conn(conn),
      api_key: conn.private[:markdow_api_key] || Application.get_env(:markdow, :api_key),
      network_address: conn.remote_ip |> :inet.ntoa() |> to_string()
    ]
  end
end

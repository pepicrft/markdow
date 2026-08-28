defmodule MarkdowWeb.ClaimController do
  @moduledoc false

  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Markdow.Accounts
  alias Markdow.AgentAuth
  alias Markdow.Index
  alias MarkdowWeb.PublicOrigin
  alias MarkdowWeb.UserAuth
  alias OpenApiSpex.Schema

  tags ["Agent authentication"]
  security []

  operation :show,
    operation_id: "show_agent_claim",
    summary: "Sign in by email to confirm an agent claim",
    parameters: [claim_attempt_token: [in: :query, type: :string, required: true]],
    responses: [ok: {"Claim page", "text/html", %Schema{type: :string}}]

  operation :resend,
    operation_id: "resend_agent_claim_email_link",
    summary: "Send another one-time email link for an agent claim",
    request_body:
      {"Claim", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{claim_attempt_token: %Schema{type: :string}},
         required: [:claim_attempt_token]
       }},
    responses: [ok: {"Email sent", "text/html", %Schema{type: :string}}]

  operation :confirm,
    operation_id: "confirm_agent_claim",
    summary: "Confirm an agent claim as the authenticated email owner",
    request_body:
      {"Confirmation", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{claim_attempt_token: %Schema{type: :string}},
         required: [:claim_attempt_token]
       }},
    responses: [ok: {"Claim confirmed", "text/html", %Schema{type: :string}}]

  operation :sign_out,
    operation_id: "sign_out_agent_claim_user",
    summary: "End the claim browser session",
    request_body:
      {"Claim", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{claim_attempt_token: %Schema{type: :string}},
         required: [:claim_attempt_token]
       }},
    responses: [found: {"Signed out", "text/html", %Schema{type: :string}}]

  def show(conn, %{"claim_attempt_token" => token}) do
    case AgentAuth.record_claim_visit(token, auth_opts(conn)) do
      {:ok, registration} -> render_claim(conn, registration, token)
      {:error, _reason} -> send_page(conn, 404, unavailable_page())
    end
  end

  def show(conn, _params), do: send_page(conn, 404, unavailable_page())

  def resend(conn, %{"claim_attempt_token" => token}) do
    with {:ok, registration} <- AgentAuth.get_claim_attempt(token, auth_opts(conn)),
         {:ok, conn} <- send_login_link(registration, token, conn) do
      send_page(
        conn,
        200,
        email_pending_page(registration, token, "We sent another secure link.")
      )
    else
      {:error, reason} -> render_delivery_error(conn, token, reason)
    end
  end

  def resend(conn, _params), do: send_page(conn, 404, unavailable_page())

  def confirm(conn, %{"claim_attempt_token" => token}) do
    with %{id: _user_id} = user <- conn.assigns.current_user,
         {:ok, _registration} <- AgentAuth.confirm_claim(token, user, auth_opts(conn)) do
      send_page(conn, 200, confirmed_page())
    else
      nil -> redirect(conn, to: claim_path(token))
      {:error, :account_mismatch} -> send_page(conn, 403, account_mismatch_page(token))
      {:error, _reason} -> send_page(conn, 422, unavailable_page())
    end
  end

  def confirm(conn, _params), do: send_page(conn, 404, unavailable_page())

  def sign_out(conn, %{"claim_attempt_token" => token}) do
    UserAuth.log_out_user(conn, claim_path(token))
  end

  def sign_out(conn, _params), do: send_page(conn, 404, unavailable_page())

  defp render_claim(conn, %{status: "claimed"}, _token),
    do: send_page(conn, 200, confirmed_page())

  defp render_claim(conn, registration, token) do
    case conn.assigns.current_user do
      %{email: email, email_verified_at: %DateTime{}} = user
      when email == registration.claim_email ->
        send_page(conn, 200, confirmation_page(user, token))

      %{email: email} when email == registration.claim_email ->
        case send_login_link(registration, token, conn) do
          {:ok, conn} -> send_page(conn, 200, email_pending_page(registration, token, nil))
          {:error, reason} -> render_delivery_error(conn, token, reason)
        end

      %{email: email} ->
        send_page(conn, 403, account_mismatch_page(token, email))

      nil ->
        case send_login_link(registration, token, conn) do
          {:ok, conn} -> send_page(conn, 200, email_pending_page(registration, token, nil))
          {:error, reason} -> render_delivery_error(conn, token, reason)
        end
    end
  end

  defp send_login_link(registration, token, conn) do
    conn = put_session(conn, :markdow_user_return_to, claim_path(token))

    with {:ok, user} <-
           Accounts.find_or_create_by_email(registration.claim_email, index(conn).repo),
         {:ok, _email} <-
           Accounts.deliver_login_link(
             user,
             &login_url(&1, conn),
             index(conn).email_notifier,
             index(conn).repo
           ) do
      {:ok, conn}
    end
  end

  defp render_delivery_error(conn, token, _reason) do
    Logger.error("Agent claim email could not be delivered")

    case AgentAuth.get_claim_attempt(token, auth_opts(conn)) do
      {:ok, registration} ->
        send_page(
          conn,
          503,
          email_pending_page(
            registration,
            token,
            "We could not send the email. Please try again."
          )
        )

      {:error, _reason} ->
        send_page(conn, 404, unavailable_page())
    end
  end

  defp confirmation_page(user, token) do
    page("""
    <h1>Confirm agent access</h1>
    <p data-part="lead">Signed in as #{email_address(user.email)}. Confirm that this agent may access only the vaults you own.</p>
    <form method="post" action="/agent/identity/claim/confirm">
      #{csrf_field()}
      <input type="hidden" name="claim_attempt_token" value="#{escape(token)}">
      <button type="submit">Confirm access</button>
    </form>
    <form method="post" action="/agent/identity/claim/sign-out" data-part="secondary-form">
      #{csrf_field()}
      <input type="hidden" name="claim_attempt_token" value="#{escape(token)}">
      <button type="submit" data-part="secondary-button">Use another account</button>
    </form>
    """)
  end

  defp email_pending_page(registration, token, notice) do
    page("""
    <h1>Check your email</h1>
    <p data-part="lead">We sent a secure, one-time sign-in link to #{email_address(registration.claim_email)}. Open it to authenticate, then review the requested access.</p>
    #{notice(notice)}
    <form method="post" action="/agent/identity/claim/resend-email-link">
      #{csrf_field()}
      <input type="hidden" name="claim_attempt_token" value="#{escape(token)}">
      <button type="submit" data-part="secondary-button">Send another link</button>
    </form>
    <p data-part="notice">The agent never receives the email link and cannot access a vault without your confirmation.</p>
    """)
  end

  defp confirmed_page do
    page("""
    <h1>Access confirmed</h1>
    <p data-part="lead">You can close this page and return to the agent.</p>
    """)
  end

  defp account_mismatch_page(token, email \\ nil) do
    signed_in = if email, do: " You are signed in as #{email_address(email)}.", else: ""

    page("""
    <h1>Use the requested account</h1>
    <p data-part="lead">This request belongs to a different email address.#{signed_in}</p>
    <form method="post" action="/agent/identity/claim/sign-out">
      #{csrf_field()}
      <input type="hidden" name="claim_attempt_token" value="#{escape(token)}">
      <button type="submit" data-part="secondary-button">Switch account</button>
    </form>
    """)
  end

  defp unavailable_page do
    page("""
    <h1>Access unavailable</h1>
    <p data-part="lead">This request is invalid, expired, or could not be confirmed.</p>
    <p data-part="notice">Ask the agent to start a new request, then open the fresh link it gives you.</p>
    """)
  end

  defp page(content) do
    MarkdowWeb.Theme.inject("""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex,nofollow">
        <title>Agent access · Markdow</title>
        <style>
          /* markdow-theme */
          body { margin: 0; background: var(--paper); color: var(--ink); font-family: var(--serif); line-height: var(--leading-normal); }
          main { width: min(640px, calc(100% - 48px)); margin: 0 auto; padding: var(--space-11) 0; }
          h1 { margin: 0 0 var(--space-4); font: var(--text-heading)/var(--leading-tight) var(--sans); }
          p { margin: 0 0 var(--space-6); color: var(--muted); }
          [data-part="lead"] { font-size: var(--text-lead); }
          [data-part="notice"] { padding-top: var(--space-5); border-top: var(--rule-width) solid var(--rule); font: var(--text-small)/var(--leading-normal) var(--sans); }
          form { display: grid; gap: var(--space-3); margin-top: var(--space-5); }
          button { width: fit-content; border: var(--rule-width) solid var(--accent); padding: var(--space-4) var(--space-6); background: var(--accent); color: var(--ink-inverted); font: var(--weight-semibold) var(--text-label)/var(--leading-flat) var(--sans); cursor: pointer; }
          [data-part="secondary-form"] { margin-top: var(--space-3); }
          [data-part="secondary-button"] { border-color: var(--rule); background: transparent; color: var(--ink); }
        </style>
      </head>
      <body><main>#{content}</main></body>
    </html>
    """)
  end

  defp notice(nil), do: ""
  defp notice(value), do: ~s(<p data-part="notice">#{escape(value)}</p>)
  defp email_address(value), do: ~s(<strong>#{escape(value)}</strong>)

  defp csrf_field,
    do:
      ~s(<input type="hidden" name="_csrf_token" value="#{Plug.CSRFProtection.get_csrf_token()}">)

  defp claim_path(token),
    do: "/agent/identity/claim?claim_attempt_token=" <> URI.encode_www_form(token)

  defp login_url(token, conn),
    do: PublicOrigin.from_conn(conn) <> "/accounts/log-in/" <> URI.encode_www_form(token)

  defp send_page(conn, status, body) do
    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header(
      "content-security-policy",
      "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
    )
    |> send_resp(status, body)
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp auth_opts(conn) do
    [
      index: index(conn),
      issuer: PublicOrigin.from_conn(conn),
      api_key: conn.private[:markdow_api_key] || Application.get_env(:markdow, :api_key),
      network_address: conn.remote_ip |> :inet.ntoa() |> to_string()
    ]
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end

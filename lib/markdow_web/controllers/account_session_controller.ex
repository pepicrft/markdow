defmodule MarkdowWeb.AccountSessionController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Markdow.Accounts
  alias Markdow.Index
  alias MarkdowWeb.PublicOrigin
  alias MarkdowWeb.UserAuth
  alias OpenApiSpex.Schema

  tags ["Authentication"]
  security []

  operation :new,
    operation_id: "show_email_login",
    summary: "Show the email-link sign-in page",
    parameters: [email: [in: :query, type: :string, required: false]],
    responses: [ok: {"Sign-in page", "text/html", %Schema{type: :string}}]

  operation :create,
    operation_id: "request_email_login",
    summary: "Send a one-time email sign-in link",
    request_body:
      {"Email address", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{email: %Schema{type: :string, format: :email}},
         required: [:email]
       }},
    responses: [
      ok: {"Email sent", "text/html", %Schema{type: :string}},
      forbidden: {"Sign-ups are disabled", "text/html", %Schema{type: :string}}
    ]

  operation :confirm,
    operation_id: "consume_email_login",
    summary: "Consume a one-time email sign-in link",
    parameters: [token: [in: :path, type: :string, required: true]],
    responses: [found: {"Signed in", "text/html", %Schema{type: :string}}]

  def new(conn, params), do: send_page(conn, 200, login_page(params["email"], nil))

  def create(conn, %{"email" => email}) when is_binary(email) do
    case send_login_link(email, conn) do
      :ok ->
        send_page(conn, 200, login_page(email, "Check your email for a secure sign-in link."))

      {:error, %Ecto.Changeset{}} ->
        send_page(conn, 422, login_page(email, "Enter a valid email address."))

      {:error, :signups_disabled} ->
        send_page(conn, 403, login_page(email, "New registrations are closed."))

      {:error, _reason} ->
        Logger.error("Email login link could not be delivered")

        send_page(
          conn,
          503,
          login_page(email, "We could not send the sign-in link. Please try again.")
        )
    end
  end

  def create(conn, _params),
    do: send_page(conn, 422, login_page(nil, "Enter a valid email address."))

  def confirm(conn, %{"token" => token}) do
    case Accounts.login_user_by_email_link(token, index(conn).repo) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      {:error, :invalid_token} ->
        conn
        |> put_status(:see_other)
        |> redirect(to: "/accounts/log-in")
    end
  end

  defp send_login_link(email, conn) do
    with {:ok, user} <-
           Accounts.find_or_create_by_email(
             email,
             index(conn).repo,
             signups_enabled: index(conn).signups_enabled
           ),
         {:ok, _email} <-
           Accounts.deliver_login_link(
             user,
             &login_url(&1, conn),
             index(conn).email_notifier,
             index(conn).repo
           ) do
      :ok
    end
  end

  defp login_url(token, conn),
    do: PublicOrigin.from_conn(conn) <> "/accounts/log-in/" <> URI.encode_www_form(token)

  defp login_page(email, notice) do
    email = if is_binary(email), do: escape(email), else: ""

    MarkdowWeb.Theme.inject("""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex,nofollow">
        <title>Sign in · Markdow</title>
        <style>
          /* markdow-theme */
          body { margin: 0; background: var(--paper); color: var(--ink); font-family: var(--serif); line-height: var(--leading-normal); }
          main { width: min(560px, calc(100% - 48px)); margin: 0 auto; padding: var(--space-11) 0; }
          h1 { margin: 0 0 var(--space-4); font: var(--text-heading)/var(--leading-tight) var(--sans); }
          p { margin: 0 0 var(--space-6); color: var(--muted); }
          form { display: grid; gap: var(--space-3); }
          label { font: var(--weight-medium) var(--text-label)/var(--leading-snug) var(--sans); }
          input { width: 100%; padding: var(--space-4); border: var(--rule-width) solid var(--rule); border-radius: 0; background: var(--paper); color: var(--ink); font: var(--text-body)/var(--leading-snug) var(--sans); }
          button { width: fit-content; border: var(--rule-width) solid var(--accent); padding: var(--space-4) var(--space-6); background: var(--accent); color: var(--ink-inverted); font: var(--weight-semibold) var(--text-label)/var(--leading-flat) var(--sans); cursor: pointer; }
          [data-part="notice"] { padding: var(--space-4); border-left: var(--accent-width) solid var(--accent); background: var(--wash); color: var(--ink); }
        </style>
      </head>
      <body>
        <main>
          <h1>Sign in to Markdow</h1>
          <p>Enter your email and we will send a secure, one-time link. There is no password to manage.</p>
          #{notice(notice)}
          <form method="post" action="/accounts/log-in">
            #{csrf_field()}
            <label for="email">Email</label>
            <input id="email" name="email" type="email" autocomplete="email" value="#{email}" required autofocus>
            <button type="submit">Email sign-in link</button>
          </form>
        </main>
      </body>
    </html>
    """)
  end

  defp notice(nil), do: ""
  defp notice(value), do: ~s(<p data-part="notice">#{escape(value)}</p>)

  defp csrf_field,
    do:
      ~s(<input type="hidden" name="_csrf_token" value="#{Plug.CSRFProtection.get_csrf_token()}">)

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

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end

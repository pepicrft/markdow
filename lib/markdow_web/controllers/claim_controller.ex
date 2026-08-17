defmodule MarkdowWeb.ClaimController do
  use MarkdowWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Markdow.Accounts
  alias Markdow.AgentAuth
  alias Markdow.Index
  alias OpenApiSpex.Schema

  tags ["Agent authentication"]
  security []

  operation :show,
    operation_id: "show_agent_claim",
    summary: "Sign in or confirm an agent claim",
    parameters: [
      claim_attempt_token: [in: :query, type: :string, required: true]
    ],
    responses: [ok: {"Claim page", "text/html", %Schema{type: :string}}]

  operation :sign_up,
    operation_id: "sign_up_agent_claim_user",
    summary: "Create the account named by an agent claim",
    request_body:
      {"Account", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{
           claim_attempt_token: %Schema{type: :string},
           name: %Schema{type: :string},
           password: %Schema{type: :string, format: :password, writeOnly: true}
         },
         required: [:claim_attempt_token, :name, :password]
       }},
    responses: [found: {"Continue to confirmation", "text/html", %Schema{type: :string}}]

  operation :sign_in,
    operation_id: "sign_in_agent_claim_user",
    summary: "Sign in to the account named by an agent claim",
    request_body:
      {"Credentials", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{
           claim_attempt_token: %Schema{type: :string},
           password: %Schema{type: :string, format: :password, writeOnly: true}
         },
         required: [:claim_attempt_token, :password]
       }},
    responses: [found: {"Continue to confirmation", "text/html", %Schema{type: :string}}]

  operation :confirm,
    operation_id: "confirm_agent_claim",
    summary: "Confirm an agent claim as the signed-in user",
    request_body:
      {"Confirmation", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{
           claim_attempt_token: %Schema{type: :string},
           user_code: %Schema{type: :string, minLength: 6, maxLength: 6}
         },
         required: [:claim_attempt_token, :user_code]
       }},
    responses: [ok: {"Claim confirmed", "text/html", %Schema{type: :string}}]

  operation :show_email_verification,
    operation_id: "show_agent_claim_email_verification",
    summary: "Review an email verification link",
    parameters: [
      email_verification_token: [in: :query, type: :string, required: true],
      claim_attempt_token: [in: :query, type: :string, required: true]
    ],
    responses: [ok: {"Email verification page", "text/html", %Schema{type: :string}}]

  operation :verify_email,
    operation_id: "verify_agent_claim_email",
    summary: "Verify the account email for an agent claim",
    request_body:
      {"Verification", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{
           email_verification_token: %Schema{type: :string, writeOnly: true},
           claim_attempt_token: %Schema{type: :string}
         },
         required: [:email_verification_token, :claim_attempt_token]
       }},
    responses: [found: {"Continue to claim confirmation", "text/html", %Schema{type: :string}}]

  operation :resend_email_verification,
    operation_id: "resend_agent_claim_email_verification",
    summary: "Send another email verification link",
    request_body:
      {"Claim", "application/x-www-form-urlencoded",
       %Schema{
         type: :object,
         properties: %{claim_attempt_token: %Schema{type: :string}},
         required: [:claim_attempt_token]
       }},
    responses: [ok: {"Verification pending", "text/html", %Schema{type: :string}}]

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
    responses: [found: {"Return to sign-in", "text/html", %Schema{type: :string}}]

  def show(conn, %{"claim_attempt_token" => token}) do
    case AgentAuth.record_claim_visit(token, auth_opts(conn)) do
      {:ok, %{status: "claimed"}} ->
        send_page(conn, 200, confirmed_page())

      {:ok, registration} ->
        render_claim_step(conn, registration, token)

      {:error, _reason} ->
        send_page(conn, 404, unavailable_page())
    end
  end

  def show(conn, _params), do: send_page(conn, 404, unavailable_page())

  def sign_up(conn, %{
        "claim_attempt_token" => token,
        "name" => name,
        "password" => password
      }) do
    with {:ok, registration} <- AgentAuth.get_claim_attempt(token, auth_opts(conn)),
         {:ok, user} <-
           Accounts.claim_user(registration.claim_email, name, password, index(conn).repo),
         {:ok, _email} <- deliver_email_verification(user, token, conn) do
      conn
      |> put_session(:markdow_user_id, user.id)
      |> put_status(:see_other)
      |> redirect(to: claim_path(token))
    else
      {:error, reason} -> render_account_error(conn, token, reason)
    end
  end

  def sign_up(conn, %{"claim_attempt_token" => token}),
    do: render_account_error(conn, token, :invalid_request)

  def sign_up(conn, _params), do: send_page(conn, 404, unavailable_page())

  def sign_in(conn, %{"claim_attempt_token" => token, "password" => password}) do
    with {:ok, registration} <- AgentAuth.get_claim_attempt(token, auth_opts(conn)),
         {:ok, user} <-
           Accounts.authenticate_user(registration.claim_email, password, index(conn).repo),
         :ok <- ensure_verification_email(user, token, conn) do
      conn
      |> put_session(:markdow_user_id, user.id)
      |> put_status(:see_other)
      |> redirect(to: claim_path(token))
    else
      {:error, :invalid_credentials} ->
        AgentAuth.record_sign_in_failure(token, auth_opts(conn))
        render_account_error(conn, token, :invalid_credentials)

      {:error, reason} ->
        render_account_error(conn, token, reason)
    end
  end

  def sign_in(conn, %{"claim_attempt_token" => token}),
    do: render_account_error(conn, token, :invalid_credentials)

  def sign_in(conn, _params), do: send_page(conn, 404, unavailable_page())

  def show_email_verification(conn, %{
        "email_verification_token" => email_token,
        "claim_attempt_token" => claim_token
      }) do
    with {:ok, user} <-
           Accounts.get_user_by_email_verification_token(email_token, index(conn).repo),
         {:ok, registration} <- AgentAuth.get_claim_attempt(claim_token, auth_opts(conn)),
         true <- user.email == registration.claim_email do
      send_page(conn, 200, email_verification_page(email_token, claim_token, user.email))
    else
      _invalid -> send_page(conn, 404, unavailable_page())
    end
  end

  def show_email_verification(conn, _params),
    do: send_page(conn, 404, unavailable_page())

  def verify_email(conn, %{
        "email_verification_token" => email_token,
        "claim_attempt_token" => claim_token
      }) do
    with {:ok, pending_user} <-
           Accounts.get_user_by_email_verification_token(email_token, index(conn).repo),
         {:ok, registration} <- AgentAuth.get_claim_attempt(claim_token, auth_opts(conn)),
         true <- pending_user.email == registration.claim_email,
         {:ok, user} <- Accounts.verify_user_email(email_token, index(conn).repo) do
      conn
      |> put_session(:markdow_user_id, user.id)
      |> put_status(:see_other)
      |> redirect(to: claim_path(claim_token))
    else
      _invalid -> send_page(conn, 404, unavailable_page())
    end
  end

  def verify_email(conn, _params), do: send_page(conn, 404, unavailable_page())

  def resend_email_verification(conn, %{"claim_attempt_token" => token}) do
    with {:ok, registration} <- AgentAuth.get_claim_attempt(token, auth_opts(conn)),
         {:ok, %{email: email} = user} <- current_user(conn),
         true <- email == registration.claim_email,
         true <- is_nil(user.email_verified_at),
         {:ok, _email} <- deliver_email_verification(user, token, conn) do
      send_page(conn, 200, email_verification_pending_page(registration, token, nil))
    else
      _invalid -> send_page(conn, 422, unavailable_page())
    end
  end

  def resend_email_verification(conn, _params),
    do: send_page(conn, 404, unavailable_page())

  def confirm(conn, %{"claim_attempt_token" => token, "user_code" => user_code}) do
    with {:ok, user} <- current_user(conn),
         {:ok, _registration} <-
           AgentAuth.confirm_claim(token, user_code, user, auth_opts(conn)) do
      send_page(conn, 200, confirmed_page())
    else
      {:error, :not_authenticated} ->
        redirect(conn, to: claim_path(token))

      {:error, :account_mismatch} ->
        send_page(conn, 403, account_mismatch_page(token))

      {:error, _reason} ->
        render_confirmation_error(conn, token)
    end
  end

  def confirm(conn, %{"claim_attempt_token" => token}),
    do: render_confirmation_error(conn, token)

  def confirm(conn, _params), do: send_page(conn, 404, unavailable_page())

  def sign_out(conn, %{"claim_attempt_token" => token}) do
    conn
    |> delete_session(:markdow_user_id)
    |> put_status(:see_other)
    |> redirect(to: claim_path(token))
  end

  def sign_out(conn, _params), do: send_page(conn, 404, unavailable_page())

  defp render_claim_step(conn, registration, token) do
    case current_user(conn) do
      {:ok, %{email: email} = user} when email == registration.claim_email ->
        if user.email_verified_at do
          send_page(conn, 200, confirmation_page(registration, token, user, nil))
        else
          send_page(conn, 200, email_verification_pending_page(registration, token, nil))
        end

      {:ok, user} ->
        send_page(conn, 403, account_mismatch_page(token, user.email))

      {:error, _reason} ->
        send_page(conn, 200, authentication_page(registration, token, nil))
    end
  end

  defp render_account_error(conn, token, reason) do
    case AgentAuth.get_claim_attempt(token, auth_opts(conn)) do
      {:ok, registration} ->
        send_page(
          conn,
          422,
          authentication_page(registration, token, account_error(reason))
        )

      {:error, _reason} ->
        send_page(conn, 404, unavailable_page())
    end
  end

  defp render_confirmation_error(conn, token) do
    with {:ok, registration} <- AgentAuth.get_claim_attempt(token, auth_opts(conn)),
         {:ok, user} <- current_user(conn) do
      send_page(
        conn,
        422,
        confirmation_page(registration, token, user, "That code is invalid or has expired.")
      )
    else
      _error -> send_page(conn, 422, unavailable_page())
    end
  end

  defp authentication_page(registration, token, error) do
    page("account", """
    <h1>Sign in or create your account</h1>
    <p data-part="lead">An agent requested access for #{email_address(registration.claim_email)}.</p>
    #{steps(:account)}
    #{error_message(error)}
    <section>
      <h2>Already use Markdow?</h2>
      <form method="post" action="/agent/identity/claim/sign-in">
        #{csrf_field()}
        <input type="hidden" name="claim_attempt_token" value="#{escape(token)}">
        <label for="sign-in-password">Password</label>
        <input id="sign-in-password" name="password" type="password" autocomplete="current-password" minlength="12" maxlength="72" required>
        <button type="submit">Sign in</button>
      </form>
    </section>
    <section data-part="account-choice">
      <h2>New to Markdow?</h2>
      <form method="post" action="/agent/identity/claim/sign-up">
        #{csrf_field()}
        <input type="hidden" name="claim_attempt_token" value="#{escape(token)}">
        <label for="name">Your name</label>
        <input id="name" name="name" autocomplete="name" maxlength="160" required>
        <label for="sign-up-password">Password</label>
        <input id="sign-up-password" name="password" type="password" autocomplete="new-password" minlength="12" maxlength="72" required aria-describedby="sign-up-password-hint">
        <p id="sign-up-password-hint" data-part="hint">At least 12 characters.</p>
        <button type="submit">Create account</button>
      </form>
    </section>
    <p data-part="notice">The agent's six-digit code is entered on the next screen, once this account is confirmed. The code stays with you. Do not send it back to the agent.</p>
    """)
  end

  defp confirmation_page(_registration, token, user, error) do
    page("code", """
    <h1>Confirm agent access</h1>
    <p data-part="lead">Signed in as #{email_address(user.email)}. Enter the six-digit code shown by your agent.</p>
    #{steps(:code)}
    #{error_message(error)}
    <form method="post" action="/agent/identity/claim/confirm">
      #{csrf_field()}
      <input type="hidden" name="claim_attempt_token" value="#{escape(token)}">
      <label for="user-code">Confirmation code</label>
      <input id="user-code" data-part="code-input" name="user_code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" required autofocus>
      <button type="submit">Confirm access</button>
    </form>
    <form method="post" action="/agent/identity/claim/sign-out" data-part="secondary-form">
      #{csrf_field()}
      <input type="hidden" name="claim_attempt_token" value="#{escape(token)}">
      <button type="submit" data-part="secondary-button">Use another account</button>
    </form>
    <p data-part="notice">This grants access only to your account and its vaults.</p>
    """)
  end

  defp email_verification_pending_page(registration, token, error) do
    page("email", """
    <h1>Verify your email</h1>
    <p data-part="lead">We sent a one-time verification link to #{email_address(registration.claim_email)}. Open it before entering the code shown by your agent.</p>
    #{steps(:email)}
    #{error_message(error)}
    <form method="post" action="/agent/identity/claim/resend-email-verification">
      #{csrf_field()}
      <input type="hidden" name="claim_attempt_token" value="#{escape(token)}">
      <button type="submit" data-part="secondary-button">Send another link</button>
    </form>
    <p data-part="notice">The email link expires after 15 minutes. The agent never receives it.</p>
    """)
  end

  defp email_verification_page(email_token, claim_token, email) do
    page("email", """
    <h1>Verify your email</h1>
    <p data-part="lead">Confirm that you control #{email_address(email)}. This does not grant the agent access until you also enter its six-digit code.</p>
    #{steps(:email)}
    <form method="post" action="/agent/identity/claim/verify-email">
      #{csrf_field()}
      <input type="hidden" name="email_verification_token" value="#{escape(email_token)}">
      <input type="hidden" name="claim_attempt_token" value="#{escape(claim_token)}">
      <button type="submit">Verify email</button>
    </form>
    """)
  end

  defp confirmed_page do
    page("done", """
    <h1>Access confirmed</h1>
    <p data-part="lead">You can close this page and return to the agent.</p>
    #{steps(:done)}
    """)
  end

  defp account_mismatch_page(token, email \\ nil) do
    signed_in = if email, do: " You are signed in as #{email_address(email)}.", else: ""

    page("account", """
    <h1>Use the requested account</h1>
    <p data-part="lead">This request belongs to a different email address.#{signed_in}</p>
    <form method="post" action="/agent/identity/claim/sign-out">
      #{csrf_field()}
      <input type="hidden" name="claim_attempt_token" value="#{escape(token)}">
      <button type="submit">Switch account</button>
    </form>
    """)
  end

  defp unavailable_page do
    page("unavailable", """
    <h1>Access unavailable</h1>
    <p data-part="lead">This request is invalid, expired, or could not be confirmed.</p>
    <p data-part="notice">Ask the agent to start a new request, then open the fresh link it gives you.</p>
    """)
  end

  @steps [account: "Account", email: "Verify email", code: "Enter code"]

  # The claim runs across three screens, so every step renders the whole
  # sequence. Someone who lands on the password form can see that the agent's
  # code is asked for later rather than looking for a field that is not there
  # yet.
  defp steps(current) do
    order = Keyword.keys(@steps)
    current_position = Enum.find_index(order, &(&1 == current))

    items =
      @steps
      |> Enum.with_index(1)
      |> Enum.map_join(fn {{step, label}, position} ->
        """
        <li data-step="#{step}" data-state="#{step_state(position, current_position)}">\
        <span data-part="index">Step #{position}</span>#{escape(label)}</li>
        """
      end)

    ~s(<ol data-part="steps">#{items}</ol>)
  end

  defp step_state(_position, nil), do: "done"
  defp step_state(position, current_position) when position == current_position + 1, do: "current"
  defp step_state(position, current_position) when position <= current_position, do: "done"
  defp step_state(_position, _current_position), do: "upcoming"

  # Cloudflare rewrites bare addresses into a script-backed placeholder, and
  # this page's content security policy blocks the script that would decode it.
  # The opt-out comments keep the address readable to the person confirming it.
  defp email_address(value) do
    ~s(<strong data-part="email"><!--email_off-->#{escape(value)}<!--email_on--></strong>)
  end

  defp page(step, content) do
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

          * { box-sizing: border-box; }
          body { margin: 0; background: var(--paper); color: var(--ink); font-family: var(--serif); font-size: var(--text-root); line-height: var(--leading-normal); }
          a { color: var(--accent); text-underline-offset: 3px; }

          #agent-claim {
            --page-width: 640px;
            --page-gutter: 40px;

            display: flex;
            flex-direction: column;
            min-height: 100vh;
            margin: 0 auto;
            width: min(var(--page-width), calc(100% - var(--page-gutter)));

            & > [data-part="masthead"] {
              display: flex;
              justify-content: space-between;
              gap: var(--space-6);
              padding: var(--space-6) 0;
              border-bottom: var(--rule-width) solid var(--ink);
              font: var(--text-small)/var(--leading-snug) var(--sans);

              & a { color: var(--ink); text-decoration: none; }
              & > [data-part="context"] { color: var(--muted); }
            }

            & > [data-part="body"] {
              flex: 1;
              padding: var(--space-10) 0 var(--space-11);

              @media (max-width: 620px) {
                & { padding: var(--space-9) 0 var(--space-10); }
              }

              & h1 {
                margin: 0 0 var(--space-4);
                font-family: var(--sans);
                font-size: var(--text-heading);
                letter-spacing: var(--tracking-heading);
                line-height: var(--leading-tight);
              }

              & h2 {
                margin: 0;
                font-family: var(--sans);
                font-size: var(--text-feature);
                letter-spacing: var(--tracking-heading);
                line-height: var(--leading-tight);
              }

              & > [data-part="lead"] {
                margin: 0 0 var(--space-8);
                color: var(--muted);
                font-size: var(--text-lead);

                & > [data-part="email"] { color: var(--ink); font-weight: var(--weight-medium); }
              }

              & > section {
                padding: var(--space-7) 0;
                border-top: var(--rule-width) solid var(--rule);
              }

              & > [data-part="notice"] {
                margin: var(--space-8) 0 0;
                padding-top: var(--space-5);
                border-top: var(--rule-width) solid var(--rule);
                color: var(--muted);
                font: var(--text-small)/var(--leading-normal) var(--sans);
              }

              & > [data-part="error"] {
                margin: 0 0 var(--space-6);
                padding-left: var(--space-4);
                border-left: var(--accent-width) solid var(--negative-rule);
                font-size: var(--text-meta);
              }
            }

            & [data-part="steps"] {
              display: flex;
              gap: var(--space-4);
              margin: 0 0 var(--space-9);
              padding: 0;
              list-style: none;
              font: var(--text-mini)/var(--leading-snug) var(--sans);

              & > li {
                flex: 1;
                padding-top: var(--space-3);
                border-top: var(--accent-width) solid var(--rule);
                color: var(--muted);
              }

              & > li[data-state="done"] { border-color: var(--accent); }

              & > li[data-state="current"] {
                border-color: var(--accent);
                color: var(--ink);
                font-weight: var(--weight-semibold);
              }

              & [data-part="index"] {
                display: block;
                margin-bottom: var(--space-1);
                font: var(--text-micro)/var(--leading-flat) var(--mono);
                letter-spacing: .12em;
                text-transform: uppercase;
              }
            }

            & form {
              display: grid;
              gap: var(--space-2);
              margin-top: var(--space-5);
            }

            & label {
              font: var(--weight-medium) var(--text-label)/var(--leading-snug) var(--sans);
            }

            & [data-part="hint"] {
              margin: 0;
              color: var(--muted);
              font: var(--text-mini)/var(--leading-snug) var(--sans);
            }

            & input {
              width: 100%;
              border: var(--rule-width) solid var(--rule);
              border-radius: 0;
              padding: var(--space-4);
              background: var(--paper);
              color: var(--ink);
              font: var(--text-body)/var(--leading-snug) var(--sans);

              &:focus-visible {
                border-color: var(--accent);
                outline: var(--accent-width) solid var(--accent);
                outline-offset: var(--space-1);
              }
            }

            & [data-part="code-input"] {
              font: var(--text-feature)/var(--leading-snug) var(--mono);
              letter-spacing: .35em;
            }

            & button {
              margin-top: var(--space-3);
              border: var(--rule-width) solid var(--accent);
              border-radius: 0;
              padding: var(--space-4) var(--space-6);
              background: var(--accent);
              color: var(--ink-inverted);
              cursor: pointer;
              font: var(--weight-semibold) var(--text-label)/var(--leading-flat) var(--sans);

              &:hover { border-color: var(--ink); background: var(--ink); }

              &:focus-visible {
                outline: var(--accent-width) solid var(--ink);
                outline-offset: var(--space-1);
              }
            }

            & [data-part="secondary-form"] { margin-top: 0; }

            & [data-part="secondary-button"] {
              border-color: var(--rule);
              background: transparent;
              color: var(--ink);

              &:hover { border-color: var(--ink); background: var(--wash); color: var(--ink); }
            }

            & > [data-part="colophon"] {
              display: flex;
              justify-content: space-between;
              gap: var(--space-6);
              padding: var(--space-6) 0 var(--space-7);
              border-top: var(--rule-width) solid var(--rule);
              color: var(--muted);
              font: var(--text-mini)/var(--leading-normal) var(--sans);
            }
          }
        </style>
      </head>
      <body>
        <div id="agent-claim">
          <header data-part="masthead"><a href="/"><strong>markdow</strong></a><span data-part="context">Agent access</span></header>
          <main data-part="body" data-step="#{step}">
            #{content}
          </main>
          <footer data-part="colophon"><span>Markdow never shares your password with the agent.</span><a href="/privacy">Privacy</a></footer>
        </div>
      </body>
    </html>
    """)
  end

  defp current_user(conn) do
    case get_session(conn, :markdow_user_id) do
      user_id when is_binary(user_id) -> Accounts.get_user(user_id, index(conn).repo)
      _user_id -> {:error, :not_authenticated}
    end
  end

  defp account_error(:invalid_credentials), do: "The password is incorrect."

  # Only the fields the person typed are reported back. Whether an account
  # already exists stays out of the message, because anyone can start a claim
  # for any address and the answer would tell them who has an account.
  defp account_error(%Ecto.Changeset{} = changeset) do
    case Enum.flat_map([:name, :password], &field_errors(changeset, &1)) do
      [] -> account_error(:unknown)
      messages -> Enum.join(messages, " ")
    end
  end

  defp account_error(_reason) do
    "Those details could not be used to create an account. " <>
      "If this address already has a Markdow account, sign in with its password above instead."
  end

  defp field_errors(changeset, field) do
    changeset.errors
    |> Keyword.get_values(field)
    |> Enum.map(fn {message, opts} ->
      message =
        Regex.replace(~r/%\{(\w+)\}/, message, fn _match, key ->
          opts |> Enum.find_value("", fn {k, v} -> to_string(k) == key && to_string(v) end)
        end)

      "#{String.capitalize(to_string(field))} #{message}."
    end)
  end

  defp error_message(nil), do: ""
  defp error_message(message), do: ~s(<p data-part="error">#{escape(message)}</p>)

  defp csrf_field do
    ~s(<input type="hidden" name="_csrf_token" value="#{Plug.CSRFProtection.get_csrf_token()}">)
  end

  defp claim_path(token),
    do: "/agent/identity/claim?claim_attempt_token=" <> URI.encode_www_form(token)

  defp ensure_verification_email(%{email_verified_at: %DateTime{}}, _token, _conn), do: :ok

  defp ensure_verification_email(user, token, conn) do
    with {:ok, _email} <- deliver_email_verification(user, token, conn), do: :ok
  end

  defp deliver_email_verification(user, claim_token, conn) do
    Accounts.deliver_email_verification(
      user,
      &email_verification_url(&1, claim_token, conn),
      index(conn).email_notifier,
      index(conn).repo
    )
  end

  defp email_verification_url(email_token, claim_token, conn) do
    query =
      URI.encode_query(%{
        "email_verification_token" => email_token,
        "claim_attempt_token" => claim_token
      })

    Keyword.fetch!(auth_opts(conn), :issuer) <>
      "/agent/identity/claim/verify-email?" <> query
  end

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
      issuer: MarkdowWeb.PublicOrigin.from_conn(conn),
      api_key: conn.private[:markdow_api_key] || Application.get_env(:markdow, :api_key),
      network_address: conn.remote_ip |> :inet.ntoa() |> to_string()
    ]
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()
end

defmodule MarkdowWeb.OAuthAuthorizeController do
  @moduledoc """
  The authorization code endpoint, where a person approves a client.

  This is the half that makes open registration safe. A client registered
  anonymously has no account and can reach nothing; it becomes able to read a
  vault only once somebody has signed in here and said yes, and only for the
  account that said it.

  Signing in happens on this page and nowhere else. The client never sees the
  password, only the code this page hands back, which is why the password grant
  is refused in `Markdow.OAuth.ResourceOwners`.
  """

  use MarkdowWeb, :controller

  @behaviour Boruta.Oauth.AuthorizeApplication

  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.ResourceOwner
  alias Markdow.Accounts
  alias Markdow.Index
  alias Markdow.OAuth

  @session_key :markdow_user_id

  def show(conn, params) do
    case current_user(conn) do
      {:ok, user} -> render_consent(conn, params, user, nil)
      {:error, _reason} -> render_sign_in(conn, params, nil)
    end
  end

  def sign_in(conn, %{"email" => email, "password" => password} = params) do
    with {:ok, user} <- Accounts.authenticate_user(email, password, index(conn).repo),
         :ok <- ensure_verified(user) do
      conn
      |> put_session(@session_key, user.id)
      |> render_consent(params, user, nil)
    else
      {:error, :unverified_email} ->
        render_sign_in(
          conn,
          params,
          "Verify your email address before connecting an application."
        )

      {:error, _reason} ->
        render_sign_in(conn, params, "Those details did not match an account.")
    end
  end

  def sign_in(conn, params),
    do: render_sign_in(conn, params, "Enter the email address and password for your account.")

  def approve(conn, params) do
    case current_user(conn) do
      {:ok, user} ->
        :ok = OAuth.ensure_scopes()

        # Boruta reads the authorization request off the connection, so the
        # parameters the client sent are put back on a GET-shaped conn rather
        # than passed along.
        conn
        |> authorize_conn(params)
        |> Boruta.Oauth.authorize(
          %ResourceOwner{sub: user.id, username: user.email},
          __MODULE__
        )

      {:error, _reason} ->
        render_sign_in(conn, params, "Sign in again to approve this application.")
    end
  end

  def deny(conn, params) do
    # The specification wants the refusal delivered to the client rather than
    # shown here, so it can stop waiting and say so itself.
    case params["redirect_uri"] do
      uri when is_binary(uri) and uri != "" ->
        redirect(conn,
          external:
            uri <>
              separator(uri) <>
              URI.encode_query(%{
                "error" => "access_denied",
                "error_description" => "The account holder refused this request.",
                "state" => params["state"] || ""
              })
        )

      _missing ->
        send_page(conn, 400, page("Not connected", "This request has no reply address."))
    end
  end

  @impl Boruta.Oauth.AuthorizeApplication
  def authorize_success(conn, response) do
    redirect(conn, external: AuthorizeResponse.redirect_to_url(response))
  end

  @impl Boruta.Oauth.AuthorizeApplication
  def authorize_error(conn, %{error: error, error_description: description} = oauth_error) do
    case Map.get(oauth_error, :redirect_uri) do
      uri when is_binary(uri) and uri != "" ->
        redirect(conn,
          external:
            uri <>
              separator(uri) <>
              URI.encode_query(%{
                "error" => to_string(error),
                "error_description" => description,
                "state" => Map.get(oauth_error, :state) || ""
              })
        )

      _missing ->
        send_page(conn, 400, page("Not connected", description))
    end
  end

  defp authorize_conn(conn, params) do
    query =
      params
      |> Map.take(~w(client_id redirect_uri response_type scope state code_challenge
                     code_challenge_method resource nonce))
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    %{conn | query_params: query, params: query, method: "GET"}
  end

  defp ensure_verified(%{email_verified_at: nil}), do: {:error, :unverified_email}
  defp ensure_verified(_user), do: :ok

  defp current_user(conn) do
    case get_session(conn, @session_key) do
      user_id when is_binary(user_id) -> Accounts.get_user(user_id, index(conn).repo)
      _user_id -> {:error, :not_authenticated}
    end
  end

  defp render_sign_in(conn, params, error) do
    send_page(
      conn,
      200,
      page(
        "Connect an application",
        """
        #{error_banner(error)}
        <p>Sign in to your Markdow account to decide whether to connect this application.</p>
        <form method="post" action="/oauth2/authorize/sign-in">
          #{hidden_fields(params)}
          <label for="email">Email address</label>
          <input id="email" name="email" type="email" autocomplete="username" required>
          <label for="password">Password</label>
          <input id="password" name="password" type="password" autocomplete="current-password" required>
          <button type="submit">Sign in</button>
        </form>
        """
      )
    )
  end

  defp render_consent(conn, params, user, error) do
    send_page(
      conn,
      200,
      page(
        "Connect an application",
        """
        #{error_banner(error)}
        <p><strong>#{escape(client_name(params))}</strong> is asking to use your Markdow
        account, <span class="muted">#{escape(user.email)}</span>.</p>
        <p class="muted">It will be able to do the following, and nothing else, until you
        remove it:</p>
        <ul>#{scope_list(params)}</ul>
        <form method="post" action="/oauth2/authorize/approve">
          #{hidden_fields(params)}
          <button type="submit">Connect</button>
        </form>
        <form method="post" action="/oauth2/authorize/deny" class="secondary">
          #{hidden_fields(params)}
          <button type="submit" class="link">Do not connect</button>
        </form>
        """
      )
    )
  end

  defp client_name(params) do
    case OAuth.client_name(params["client_id"]) do
      {:ok, name} when is_binary(name) and name != "" -> name
      _other -> "An application"
    end
  end

  defp scope_list(params) do
    requested =
      (params["scope"] || "")
      |> String.split()
      |> Enum.filter(&(&1 in OAuth.scopes()))

    requested = if requested == [], do: ["mcp"], else: requested

    Enum.map_join(requested, "", &"<li>#{escape(scope_description(&1))}</li>")
  end

  defp scope_description("users:read"), do: "Read your account details"
  defp scope_description("vaults:read"), do: "See your vaults"
  defp scope_description("vaults:write"), do: "Create vaults"
  defp scope_description("notes:read"), do: "Read and search your notes"
  defp scope_description("notes:write"), do: "Write, change and delete your notes"
  defp scope_description("documents:read"), do: "Read your documents and attachments"
  defp scope_description("documents:write"), do: "Write and delete your documents"
  defp scope_description("embeddings:read"), do: "Read your embedding settings"
  defp scope_description("embeddings:write"), do: "Change your embedding settings"
  defp scope_description("mcp"), do: "Connect over the Model Context Protocol"
  defp scope_description(scope), do: scope

  defp hidden_fields(params) do
    params
    |> Map.take(~w(client_id redirect_uri response_type scope state code_challenge
                   code_challenge_method resource nonce))
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.map_join("", fn {key, value} ->
      ~s(<input type="hidden" name="#{escape(key)}" value="#{escape(value)}">)
    end)
  end

  defp error_banner(nil), do: ""
  defp error_banner(message), do: ~s(<p class="error">#{escape(message)}</p>)

  defp separator(uri), do: if(String.contains?(uri, "?"), do: "&", else: "?")

  # Same escaping the claim pages use. These pages are rendered as strings, so
  # every interpolated value passes through here, including anything a client
  # put in its registration or its authorization request.
  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp send_page(conn, status, body) do
    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, body)
  end

  defp index(conn), do: conn.private[:markdow_index] || Index.context()

  defp page(title, body) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{escape(title)} · Markdow</title>
        <style>
          :root { color-scheme: light dark; }
          body { margin: 0; min-height: 100vh; display: grid; place-items: center;
                 font: 16px/1.6 ui-sans-serif, system-ui, sans-serif; padding: 2rem; }
          main { width: min(28rem, 100%); }
          h1 { font-size: 1.35rem; margin: 0 0 1rem; }
          .muted { opacity: .7; }
          .error { padding: .75rem 1rem; border-radius: .5rem;
                   background: rgba(190, 30, 30, .12); }
          ul { padding-left: 1.1rem; }
          li { margin: .2rem 0; }
          label { display: block; margin: 1rem 0 .25rem; font-size: .9rem; }
          input[type=email], input[type=password] { width: 100%; padding: .6rem .7rem;
            border-radius: .5rem; border: 1px solid rgba(128,128,128,.5);
            background: transparent; color: inherit; font: inherit; box-sizing: border-box; }
          button { margin-top: 1.25rem; width: 100%; padding: .7rem 1rem; border: 0;
            border-radius: .5rem; font: inherit; cursor: pointer;
            background: CanvasText; color: Canvas; }
          form.secondary { margin-top: .5rem; }
          button.link { background: none; color: inherit; text-decoration: underline;
            opacity: .75; margin-top: .25rem; }
        </style>
      </head>
      <body>
        <main>
          <h1>#{escape(title)}</h1>
          #{body}
        </main>
      </body>
    </html>
    """
  end
end

defmodule Markdow.Accounts.EmailNotifier do
  @moduledoc false

  import Swoosh.Email

  alias Markdow.Accounts.User
  alias Markdow.Mailer

  @callback deliver_verification(User.t(), String.t()) ::
              {:ok, Swoosh.Email.t()} | {:error, term()}

  @spec deliver_verification(User.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_verification(%User{} = user, url) when is_binary(url) do
    {from_name, from_address} =
      Application.get_env(:markdow, :email_from, {"Markdow", "hello@markdow.org"})

    email =
      new()
      |> to(user.email)
      |> from({from_name, from_address})
      |> subject("Verify your Markdow email")
      |> text_body(text_body(url))
      |> html_body(html_body(url))

    with {:ok, _metadata} <- Mailer.deliver(email), do: {:ok, email}
  end

  defp text_body(url) do
    """
    Verify your Markdow email

    Open this secure link, then confirm the address in your browser:

    #{url}

    The link expires in 15 minutes and can only be used once. If you did not create this account, ignore this message.
    """
  end

  # Clients collapse a plain-text message into one paragraph and leave the link
  # as bare text, so the address arrives as an unreadable wall. The colors are
  # written out rather than taken from the theme because email clients do not
  # support custom properties.
  defp html_body(url) do
    href = escape(url)

    """
    <!doctype html>
    <html lang="en">
      <body style="margin:0;padding:24px;background:#f8f7f2;color:#24231f;font-family:Georgia,'Times New Roman',serif;font-size:16px;line-height:1.55;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="max-width:520px;margin:0 auto;">
          <tr>
            <td>
              <p style="margin:0 0 24px;font-family:Helvetica,Arial,sans-serif;font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#6e6b62;">Markdow</p>
              <h1 style="margin:0 0 16px;font-family:Helvetica,Arial,sans-serif;font-size:28px;line-height:1.2;">Verify your email</h1>
              <p style="margin:0 0 24px;">Confirm this address to finish setting up your Markdow account.</p>
              <p style="margin:0 0 24px;">
                <a href="#{href}" style="display:inline-block;padding:14px 24px;background:#285d4b;color:#f5f3eb;font-family:Helvetica,Arial,sans-serif;font-size:15px;font-weight:600;text-decoration:none;">Verify email address</a>
              </p>
              <p style="margin:0 0 8px;font-family:Helvetica,Arial,sans-serif;font-size:13px;color:#6e6b62;">If the button does not work, open this address in your browser:</p>
              <p style="margin:0 0 24px;font-family:Helvetica,Arial,sans-serif;font-size:13px;word-break:break-all;"><a href="#{href}" style="color:#285d4b;">#{href}</a></p>
              <p style="margin:0;padding-top:16px;border-top:1px solid #cfccc2;font-family:Helvetica,Arial,sans-serif;font-size:13px;color:#6e6b62;">The link expires in 15 minutes and can only be used once. If you did not create this account, ignore this message.</p>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  # The verification address carries two query parameters, so the ampersand
  # between them has to be escaped for the href to survive.
  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end

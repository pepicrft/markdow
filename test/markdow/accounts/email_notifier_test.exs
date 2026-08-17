defmodule Markdow.Accounts.EmailNotifierTest do
  use ExUnit.Case, async: true

  alias Markdow.Accounts.EmailNotifier
  alias Markdow.Accounts.User

  @url "https://markdow.org/agent/identity/claim/verify-email?claim_attempt_token=cla_abc&email_verification_token=tok_def"

  setup do
    {:ok, user: %User{id: "usr_test", email: "verify@example.com"}}
  end

  test "sends the verification link as a hyperlink", %{user: user} do
    assert {:ok, email} = EmailNotifier.deliver_verification(user, @url)

    assert email.html_body =~ ~s(<a href="https://markdow.org/agent/identity/claim/verify-email?)
    assert email.html_body =~ "Verify email address"
  end

  test "escapes the ampersand that separates the two query parameters", %{user: user} do
    assert {:ok, email} = EmailNotifier.deliver_verification(user, @url)

    # An unescaped ampersand inside the href truncates the address in clients
    # that parse it strictly, which would drop the verification token.
    assert email.html_body =~ "claim_attempt_token=cla_abc&amp;email_verification_token=tok_def"
    refute email.html_body =~ "cla_abc&email"
  end

  test "keeps a plain-text alternative carrying the raw address", %{user: user} do
    assert {:ok, email} = EmailNotifier.deliver_verification(user, @url)

    assert email.text_body =~ @url
    assert email.text_body =~ "expires in 15 minutes"
  end

  test "addresses the recipient and sets the subject", %{user: user} do
    assert {:ok, email} = EmailNotifier.deliver_verification(user, @url)

    assert email.to == [{"", "verify@example.com"}]
    assert email.subject == "Verify your Markdow email"
  end
end

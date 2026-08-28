defmodule Markdow.AgentAuthTest do
  use Markdow.DataCase, async: true

  alias Markdow.Accounts
  alias Markdow.AgentAuth
  alias Markdow.Repo

  @issuer "http://markdow.test"
  @email "writer@markdow.test"

  test "creates an email-bound claim without a user code", %{index: index} do
    assert {:ok, claim} =
             AgentAuth.create_service_registration(" Writer@Markdow.test ", auth_opts(index))

    assert claim.registration.claim_email == @email
    refute Map.has_key?(claim, :user_code)

    assert Repo.get!(Markdow.AgentAuth.Registration, claim.registration.id)

    assert AgentAuth.create_service_registration("not-an-email", auth_opts(index)) ==
             {:error, :invalid_login_hint}
  end

  test "issues access only after the matching verified user confirms", %{index: index} do
    opts = auth_opts(index)
    assert {:ok, claim} = AgentAuth.create_service_registration(@email, opts)
    assert {:ok, owner} = Accounts.create_user(%{"id" => "owner", "email" => @email}, index.repo)

    assert AgentAuth.exchange_claim(claim.claim_token, opts) == {:error, :authorization_pending}

    assert AgentAuth.confirm_claim(
             claim.claim_attempt_token,
             %{id: "other", email: "other@example.com", email_verified_at: DateTime.utc_now()},
             opts
           ) == {:error, :account_mismatch}

    assert AgentAuth.confirm_claim(
             claim.claim_attempt_token,
             %{owner | email_verified_at: nil},
             opts
           ) == {:error, :email_not_verified}

    assert {:ok, claimed} =
             AgentAuth.confirm_claim(
               claim.claim_attempt_token,
               %{owner | email_verified_at: DateTime.utc_now()},
               opts
             )

    assert claimed.claimed_by_user_id == "owner"

    assert {:ok, token} = AgentAuth.exchange_claim(claim.claim_token, opts)
    assert token.token_type == "Bearer"

    assert {:ok, %{user_id: "owner"}} =
             AgentAuth.authorize(
               token.access_token,
               ["vaults:read"],
               Keyword.put(opts, :resource, @issuer)
             )
  end

  defp auth_opts(index) do
    [
      index: index,
      issuer: @issuer,
      api_key: "test",
      allow_ephemeral_signing_key: true
    ]
  end
end

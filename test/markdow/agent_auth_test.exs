defmodule Markdow.AgentAuthTest do
  use Markdow.DataCase, async: true

  import Ecto.Query

  alias Markdow.Accounts
  alias Markdow.AgentAuth
  alias Markdow.AgentAuth.Event
  alias Markdow.AgentAuth.ExpirationSweeper
  alias Markdow.Repo

  @issuer "http://markdow.test"
  @email "writer@markdow.test"
  @api_key "local-secret"

  test "accepts any valid login hint and rejects malformed email", %{index: index} do
    assert {:ok, registration} =
             AgentAuth.create_service_registration(" Other@Example.com ", auth_opts(index))

    assert registration.registration.claim_email == "other@example.com"

    stored = Repo.get!(Markdow.AgentAuth.Registration, registration.registration.id)
    refute stored.user_code_hash == :crypto.hash(:sha256, registration.user_code)

    assert AgentAuth.create_service_registration("not-an-email", auth_opts(index)) ==
             {:error, :invalid_login_hint}

    oversized_email = String.duplicate("a", 250) <> "@example.com"

    assert AgentAuth.create_service_registration(oversized_email, auth_opts(index)) ==
             {:error, :invalid_login_hint}
  end

  test "completes a user-bound claim, assertion exchange, and revocation", %{index: index} do
    opts = auth_opts(index)
    user = create_user(index, @email)
    assert {:ok, registration} = AgentAuth.create_service_registration(@email, opts)

    assert AgentAuth.exchange_claim(registration.claim_token, opts) ==
             {:error, :authorization_pending}

    assert AgentAuth.confirm_claim(
             registration.claim_attempt_token,
             "invalid",
             user,
             opts
           ) == {:error, :invalid_user_code}

    assert {:ok, claimed} =
             AgentAuth.confirm_claim(
               registration.claim_attempt_token,
               registration.user_code,
               user,
               opts
             )

    assert claimed.status == "claimed"
    assert claimed.claimed_by_user_id == user.id

    assert {:ok, token_response} = AgentAuth.exchange_claim(registration.claim_token, opts)
    assert token_response.token_type == "Bearer"
    refute String.contains?(token_response.scope, "users:write")
    assert is_binary(token_response.identity_assertion)

    assert %JOSE.JWT{fields: %{"email_verified" => true}} =
             JOSE.JWT.peek_payload(token_response.identity_assertion)

    rest_opts = Keyword.put(opts, :resource, @issuer)

    assert {:ok, authorization} =
             AgentAuth.authorize(token_response.access_token, ["notes:read", "mcp"], rest_opts)

    assert authorization.registration_id == registration.registration.id
    assert authorization.user_id == user.id

    assert AgentAuth.authorize(token_response.access_token, ["users:write"], rest_opts) ==
             {:error, :insufficient_scope}

    assert AgentAuth.authorize(
             token_response.access_token,
             ["notes:read"],
             Keyword.put(opts, :resource, @issuer <> "/mcp")
           ) == {:error, :invalid_token}

    assert {:ok, refreshed} =
             AgentAuth.exchange_assertion(
               token_response.identity_assertion,
               @issuer <> "/mcp",
               opts
             )

    assert refreshed.access_token != token_response.access_token

    assert {:ok, _authorization} =
             AgentAuth.authorize(
               refreshed.access_token,
               ["notes:write"],
               Keyword.put(opts, :resource, @issuer <> "/mcp")
             )

    assert AgentAuth.exchange_assertion(
             token_response.identity_assertion,
             @issuer <> "/mcp",
             opts
           ) == {:error, :invalid_grant}

    assert :ok = AgentAuth.revoke_access_token(token_response.access_token, opts)
    assert :ok = AgentAuth.revoke_access_token(token_response.access_token, opts)

    assert AgentAuth.authorize(token_response.access_token, ["notes:read"], rest_opts) ==
             {:error, :invalid_token}

    event_names =
      Repo.all(
        from(event in Event,
          where: event.registration_id == ^registration.registration.id,
          order_by: event.id,
          select: event.name
        )
      )

    assert event_names == [
             "registration.created",
             "claim.requested",
             "user_code.minted",
             "claim.confirmed",
             "token.issued",
             "assertion.issued",
             "token.issued",
             "token.revoked"
           ]
  end

  test "keeps pending claim codes valid when the application key rotates", %{index: index} do
    user = create_user(index, @email)
    opts = Keyword.put(auth_opts(index), :user_code_hmac_key, "dedicated-user-code-key")

    assert {:ok, registration} = AgentAuth.create_service_registration(@email, opts)

    rotated_key_opts = Keyword.put(opts, :api_key, "rotated-application-key")

    assert {:ok, _claimed} =
             AgentAuth.confirm_claim(
               registration.claim_attempt_token,
               registration.user_code,
               user,
               rotated_key_opts
             )
  end

  test "accepts a pending claim minted before codes were registration-scoped", %{index: index} do
    opts = auth_opts(index)
    user = create_user(index, @email)
    assert {:ok, registration} = AgentAuth.create_service_registration(@email, opts)

    legacy_hash =
      :crypto.mac(
        :hmac,
        :sha256,
        opts[:user_code_hmac_key],
        "markdow:agent-user-code:v1:" <> registration.user_code
      )

    registration.registration.id
    |> then(&Repo.get!(Markdow.AgentAuth.Registration, &1))
    |> Ecto.Changeset.change(user_code_hash: legacy_hash)
    |> Repo.update!()

    assert {:ok, _claimed} =
             AgentAuth.confirm_claim(
               registration.claim_attempt_token,
               registration.user_code,
               user,
               opts
             )
  end

  test "rejects an authenticated account whose email differs from the login hint", %{index: index} do
    opts = auth_opts(index)
    attacker = create_user(index, "attacker@example.com")
    assert {:ok, registration} = AgentAuth.create_service_registration(@email, opts)

    assert AgentAuth.confirm_claim(
             registration.claim_attempt_token,
             registration.user_code,
             attacker,
             opts
           ) == {:error, :account_mismatch}

    assert AgentAuth.exchange_claim(registration.claim_token, opts) ==
             {:error, :authorization_pending}
  end

  test "does not confirm a matching but unverified email", %{index: index} do
    opts = auth_opts(index)
    assert {:ok, user} = Accounts.create_user(%{"email" => @email}, index.repo)
    assert {:ok, registration} = AgentAuth.create_service_registration(@email, opts)

    assert AgentAuth.confirm_claim(
             registration.claim_attempt_token,
             registration.user_code,
             user,
             opts
           ) == {:error, :email_not_verified}

    assert AgentAuth.exchange_claim(registration.claim_token, opts) ==
             {:error, :authorization_pending}
  end

  test "expires a claim after the configured number of failed code attempts", %{index: index} do
    user = create_user(index, @email)
    opts = Keyword.put(auth_opts(index), :claim_attempt_limit, 2)
    assert {:ok, registration} = AgentAuth.create_service_registration(@email, opts)

    assert AgentAuth.confirm_claim(registration.claim_attempt_token, "000000", user, opts) ==
             {:error, :invalid_user_code}

    assert AgentAuth.confirm_claim(registration.claim_attempt_token, "000001", user, opts) ==
             {:error, :expired_token}

    assert AgentAuth.confirm_claim(
             registration.claim_attempt_token,
             registration.user_code,
             user,
             opts
           ) == {:error, :expired_token}

    assert AgentAuth.exchange_claim(registration.claim_token, opts) == {:error, :expired_token}
  end

  test "expires a claim after repeated failed account sign-ins", %{index: index} do
    opts = Keyword.put(auth_opts(index), :sign_in_attempt_limit, 2)
    assert {:ok, registration} = AgentAuth.create_service_registration(@email, opts)

    assert :ok = AgentAuth.record_sign_in_failure(registration.claim_attempt_token, opts)

    assert AgentAuth.record_sign_in_failure(registration.claim_attempt_token, opts) ==
             {:error, :expired_token}

    assert AgentAuth.get_claim_attempt(registration.claim_attempt_token, opts) ==
             {:error, :expired_token}
  end

  test "applies shared hourly limits by network address and globally", %{index: index} do
    opts =
      index
      |> auth_opts()
      |> Keyword.merge(
        network_address: "192.0.2.10",
        registration_address_limit: 1,
        registration_global_limit: 2
      )

    assert {:ok, _registration} = AgentAuth.create_service_registration(@email, opts)

    assert AgentAuth.create_service_registration("second@example.com", opts) ==
             {:error, :rate_limited}

    second_address = Keyword.put(opts, :network_address, "192.0.2.11")
    assert {:ok, _registration} = AgentAuth.create_service_registration(@email, second_address)

    third_address = Keyword.put(opts, :network_address, "192.0.2.12")

    assert AgentAuth.create_service_registration(@email, third_address) ==
             {:error, :rate_limited}
  end

  test "enforces polling, expiration, duplicate confirmation, and assertion targets", %{
    index: index
  } do
    user = create_user(index, @email)
    opts = Keyword.put(auth_opts(index), :now, 100)
    assert {:ok, registration} = AgentAuth.create_service_registration(@email, opts)

    assert AgentAuth.exchange_claim(registration.claim_token, opts) ==
             {:error, :authorization_pending}

    assert AgentAuth.exchange_claim(registration.claim_token, opts) == {:error, :slow_down}

    assert {:ok, _claimed} =
             AgentAuth.confirm_claim(
               registration.claim_attempt_token,
               registration.user_code,
               user,
               opts
             )

    assert AgentAuth.confirm_claim(
             registration.claim_attempt_token,
             registration.user_code,
             user,
             opts
           ) == {:error, :already_claimed}

    assert {:ok, token} = AgentAuth.exchange_claim(registration.claim_token, opts)

    assert AgentAuth.exchange_assertion(token.identity_assertion, "https://other.test", opts) ==
             {:error, :invalid_grant}

    expiring_opts =
      auth_opts(index)
      |> Keyword.put(:now, 200)
      |> Keyword.put(:registration_ttl_seconds, 1)
      |> Keyword.put(:claim_attempt_ttl_seconds, 1)

    assert {:ok, expiring} = AgentAuth.create_service_registration(@email, expiring_opts)
    expired_opts = Keyword.put(expiring_opts, :now, 202)

    assert AgentAuth.exchange_claim(expiring.claim_token, expired_opts) ==
             {:error, :expired_token}

    assert AgentAuth.get_claim_attempt(expiring.claim_attempt_token, expired_opts) ==
             {:error, :expired_token}
  end

  test "bulk revokes all active agent credentials for one user only", %{index: index} do
    first = create_user(index, "first@example.com")
    second = create_user(index, "second@example.com")
    opts = auth_opts(index)

    first_credential = issue_token(first, opts)
    second_credential = issue_token(second, opts)

    assert {:ok, 1} = AgentAuth.revoke_user_access_tokens(first.id, opts)

    assert AgentAuth.authorize(first_credential.access_token, [], opts) ==
             {:error, :invalid_token}

    assert AgentAuth.exchange_assertion(first_credential.identity_assertion, @issuer, opts) ==
             {:error, :invalid_grant}

    assert {:ok, _authorization} = AgentAuth.authorize(second_credential.access_token, [], opts)

    assert {:ok, _refreshed} =
             AgentAuth.exchange_assertion(second_credential.identity_assertion, @issuer, opts)

    assert {:ok, 0} = AgentAuth.revoke_user_access_tokens(first.id, opts)
  end

  test "sweeps expired registrations and records the transition once", %{index: index} do
    opts =
      index
      |> auth_opts()
      |> Keyword.put(:now, 100)
      |> Keyword.put(:registration_ttl_seconds, 1)

    assert {:ok, registration} = AgentAuth.create_service_registration(@email, opts)
    assert {:ok, 1} = ExpirationSweeper.sweep(index, 102)
    assert {:ok, 0} = ExpirationSweeper.sweep(index, 103)

    assert AgentAuth.exchange_claim(
             registration.claim_token,
             Keyword.put(opts, :now, 103)
           ) == {:error, :expired_token}

    expired_events =
      Repo.aggregate(
        from(event in Event,
          where:
            event.registration_id == ^registration.registration.id and
              event.name == "registration.expired"
        ),
        :count
      )

    assert expired_events == 1
  end

  test "accepts the configured application key and publishes a signing key", %{index: index} do
    assert {:ok, %{kind: :api_key}} =
             AgentAuth.authorize(@api_key, AgentAuth.scopes(), auth_opts(index))

    assert AgentAuth.authorize("wrong", [], auth_opts(index)) == {:error, :invalid_token}

    assert {:ok, %{keys: [key]}} = AgentAuth.jwks(auth_opts(index))
    assert key["alg"] == "RS256"
    assert key["use"] == "sig"
    assert is_binary(key["kid"])
  end

  test "rejects malformed inputs and can require a configured signing key", %{index: index} do
    opts = auth_opts(index)

    assert AgentAuth.create_service_registration(nil, opts) == {:error, :invalid_request}
    assert AgentAuth.get_claim_attempt(nil, opts) == {:error, :invalid_claim_token}
    assert AgentAuth.confirm_claim(nil, nil, nil, opts) == {:error, :invalid_request}
    assert AgentAuth.exchange_claim(nil, opts) == {:error, :invalid_request}
    assert AgentAuth.exchange_claim("missing", opts) == {:error, :expired_token}
    assert AgentAuth.exchange_assertion(nil, nil, opts) == {:error, :invalid_request}
    assert AgentAuth.authorize(nil, [], opts) == {:error, :invalid_token}
    assert AgentAuth.revoke_access_token(nil, opts) == {:error, :invalid_token}

    signing_opts =
      opts
      |> Keyword.put(:private_key_pem, nil)
      |> Keyword.put(:allow_ephemeral_signing_key, false)

    assert AgentAuth.jwks(signing_opts) == {:error, :signing_key_unavailable}
  end

  defp create_user(index, email) do
    assert {:ok, user} = Accounts.create_user(%{"email" => email}, index.repo)

    index.repo.update_all(
      from(record in Markdow.Accounts.User, where: record.id == ^user.id),
      set: [email_verified_at: DateTime.utc_now()]
    )

    assert {:ok, verified_user} = Accounts.get_user(user.id, index.repo)
    verified_user
  end

  defp issue_token(user, opts) do
    assert {:ok, registration} = AgentAuth.create_service_registration(user.email, opts)

    assert {:ok, _claimed} =
             AgentAuth.confirm_claim(
               registration.claim_attempt_token,
               registration.user_code,
               user,
               opts
             )

    assert {:ok, response} = AgentAuth.exchange_claim(registration.claim_token, opts)
    response
  end

  defp auth_opts(index) do
    [
      index: index,
      issuer: @issuer,
      api_key: @api_key,
      user_code_hmac_key: "dedicated-user-code-key",
      allow_ephemeral_signing_key: true
    ]
  end
end

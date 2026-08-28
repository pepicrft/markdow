defmodule Markdow.AccountsTest do
  use Markdow.DataCase, async: true

  alias Markdow.Accounts
  alias Markdow.Accounts.EmailNotifier
  alias Markdow.Repo

  setup :verify_on_exit!

  test "creates a user with multiple vaults and lists only that user's vaults" do
    assert {:ok, user} =
             Accounts.create_user(
               %{"id" => "ada", "email" => "ada@example.com", "name" => "Ada"},
               Repo
             )

    assert {:ok, personal} =
             Accounts.create_vault(
               user.id,
               %{"id" => "personal", "name" => "Personal"},
               Repo
             )

    assert {:ok, work} =
             Accounts.create_vault(user.id, %{"id" => "work", "name" => "Work"}, Repo)

    assert {:ok, vaults} = Accounts.list_vaults(user.id, Repo)
    assert Enum.map(vaults, & &1.id) == [personal.id, work.id]
    assert Enum.all?(vaults, &(&1.user_id == user.id))
    assert personal.storage_prefix == "vaults/personal"
  end

  test "rejects duplicate users and vaults without an owner" do
    assert {:ok, _user} =
             Accounts.create_user(%{"id" => "one", "email" => "same@example.com"}, Repo)

    assert {:error, changeset} =
             Accounts.create_user(%{"id" => "two", "email" => "same@example.com"}, Repo)

    assert "has already been taken" in errors_on(changeset).email

    assert {:error, changeset} =
             Accounts.create_vault("missing", %{"id" => "orphan", "name" => "Orphan"}, Repo)

    assert "does not exist" in errors_on(changeset).user_id

    assert {:error, changeset} =
             Accounts.create_vault("one", %{"id" => "../outside", "name" => "Unsafe"}, Repo)

    assert "has invalid format" in errors_on(changeset).id
  end

  test "blocks every new-account path while registrations are closed" do
    closed = [signups_enabled: false]

    assert Accounts.create_user(%{"email" => "new@example.com"}, Repo, closed) ==
             {:error, :signups_disabled}

    assert Accounts.find_or_create_by_email("new@example.com", Repo, closed) ==
             {:error, :signups_disabled}

    assert Accounts.claim_user(
             "agent@example.com",
             "Agent",
             "correct horse battery staple",
             Repo,
             closed
           ) == {:error, :signups_disabled}

    assert Accounts.get_user_by_email("new@example.com", Repo) == {:error, :not_found}
    assert Accounts.get_user_by_email("agent@example.com", Repo) == {:error, :not_found}

    assert {:ok, existing} =
             Accounts.create_user(%{"email" => "existing@example.com"}, Repo)

    assert {:ok, signed_in} =
             Accounts.find_or_create_by_email(existing.email, Repo, closed)

    assert signed_in.id == existing.id
  end

  test "creates and authenticates an account initiated by an agent" do
    assert {:ok, user} =
             Accounts.claim_user(
               " Writer@Example.com ",
               "Writer",
               "correct horse battery staple",
               Repo
             )

    assert user.email == "writer@example.com"
    refute Map.has_key?(user, :hashed_password)
    refute Map.has_key?(user, :password)

    assert {:ok, authenticated} =
             Accounts.authenticate_user(
               "writer@example.com",
               "correct horse battery staple",
               Repo
             )

    assert authenticated.id == user.id

    assert Accounts.authenticate_user("writer@example.com", "wrong password", Repo) ==
             {:error, :invalid_credentials}

    assert Accounts.authenticate_user("writer@example.com", String.duplicate("x", 73), Repo) ==
             {:error, :invalid_credentials}

    assert Accounts.claim_user(
             "writer@example.com",
             "Replacement",
             "another secure password",
             Repo
           ) == {:error, :account_exists}
  end

  test "does not let an agent take over a seeded account and validates sign-up fields" do
    assert {:ok, seeded} =
             Accounts.create_user(%{"email" => "seeded@example.com", "name" => "Seeded"}, Repo)

    assert Accounts.claim_user(
             seeded.email,
             "Attacker",
             "correct horse battery staple",
             Repo
           ) == {:error, :account_exists}

    assert Accounts.authenticate_user(
             seeded.email,
             "correct horse battery staple",
             Repo
           ) == {:error, :invalid_credentials}

    assert {:error, changeset} =
             Accounts.claim_user("new@example.com", "", "short", Repo)

    assert "can't be blank" in errors_on(changeset).name
    assert "should be at least 12 character(s)" in errors_on(changeset).password
  end

  test "verifies an email with a short-lived one-time token" do
    assert {:ok, user} =
             Accounts.claim_user(
               "verify@example.com",
               "Verified owner",
               "correct horse battery staple",
               Repo
             )

    test_process = self()

    expect(EmailNotifier, :deliver_verification, fn delivered_user, url ->
      assert delivered_user.id == user.id
      send(test_process, {:verification_url, url})
      {:ok, %{to: delivered_user.email}}
    end)

    assert {:ok, %{to: "verify@example.com"}} =
             Accounts.deliver_email_verification(
               user,
               &"https://self-hosted.example/verify?token=#{&1}",
               EmailNotifier,
               Repo
             )

    assert_receive {:verification_url, url}
    token = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("token")

    assert {:ok, pending} = Accounts.get_user_by_email_verification_token(token, Repo)
    assert is_nil(pending.email_verified_at)

    assert {:ok, verified} = Accounts.verify_user_email(token, Repo)
    assert %DateTime{} = verified.email_verified_at

    assert Accounts.get_user_by_email_verification_token(token, Repo) ==
             {:error, :invalid_token}

    assert Accounts.verify_user_email(token, Repo) == {:error, :invalid_token}
  end

  test "expires old email verification tokens" do
    assert {:ok, user} =
             Accounts.claim_user(
               "expired@example.com",
               "Expired owner",
               "correct horse battery staple",
               Repo
             )

    test_process = self()

    expect(EmailNotifier, :deliver_verification, fn _user, url ->
      send(test_process, {:verification_url, url})
      {:ok, %{}}
    end)

    assert {:ok, _email} =
             Accounts.deliver_email_verification(
               user,
               &"https://self-hosted.example/verify?token=#{&1}",
               EmailNotifier,
               Repo
             )

    assert_receive {:verification_url, url}
    token = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("token")

    Repo.update_all(Markdow.Accounts.EmailVerificationToken,
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -16, :minute)]
    )

    assert Accounts.verify_user_email(token, Repo) == {:error, :invalid_token}
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        options |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

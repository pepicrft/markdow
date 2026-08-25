defmodule Markdow.EmbeddingsTest do
  use Markdow.DataCase, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Markdow.Accounts
  alias Markdow.Embeddings
  alias Markdow.Embeddings.Configuration
  alias Markdow.Embeddings.OpenAI
  alias Markdow.Operations
  alias Markdow.Repo
  alias Markdow.Secrets

  defmodule StubClient do
    @behaviour Markdow.Embeddings.Client

    @impl true
    def embed(%{model: "slow:" <> encoded_model} = configuration, token, _input) do
      parent =
        encoded_model |> Base.url_decode64!(padding: false) |> :erlang.binary_to_term([:safe])

      send(parent, {:slow_candidate_ready, self(), token})

      receive do
        :release -> result(configuration)
      end
    end

    def embed(configuration, _token, _input), do: result(configuration)

    defp result(configuration) do
      {:ok, %{embedding: [0.1], model: configuration.model, usage: %{}}}
    end
  end

  setup :verify_on_exit!

  # An address literal so the endpoint policy has nothing to look up. It sits in
  # the documentation range, which is public as far as the rules are concerned.
  @endpoint "https://203.0.113.10/v1/embeddings"

  # The seeded owner of the seeded vault.
  @user "local"
  @vault "default"

  test "encrypts an account credential, embeds text, and redacts every response", %{index: index} do
    # Configuring performs a real request before storing anything.
    expect(OpenAI, :embed, fn configuration, token, input ->
      assert configuration.user_id == @user
      assert configuration.endpoint == @endpoint
      assert token == "secret-provider-token"
      assert input =~ "Validate"

      {:ok,
       %{
         embedding: [0.1, 0.2, 0.3],
         model: "text-embedding-3-small",
         usage: %{"total_tokens" => 6}
       }}
    end)

    assert {:ok, configured} =
             Embeddings.put_configuration(index, @user, %{
               "endpoint" => @endpoint,
               "model" => "text-embedding-3-small",
               "dimensions" => 3,
               "token" => "secret-provider-token"
             })

    assert configured.user_id == @user
    assert configured.endpoint == @endpoint
    assert configured.credential_hint == "••••oken"
    # A stored configuration has been seen to work, so it is validated already.
    assert configured.validated_at
    refute inspect(configured) =~ "secret-provider-token"

    stored = Repo.get!(Configuration, @user)
    refute stored.token_ciphertext == "secret-provider-token"
    refute inspect(stored) =~ "secret-provider-token"

    expect(OpenAI, :embed, fn configuration, token, input ->
      assert configuration.user_id == @user
      assert token == "temporary-token"
      assert input == "A note to embed"

      {:ok,
       %{
         embedding: [0.4, 0.5, 0.6],
         model: "text-embedding-3-small",
         usage: %{"total_tokens" => 4}
       }}
    end)

    # Embedding is addressed by vault and resolves the owner's configuration.
    assert {:ok, result} =
             Embeddings.embed(index, @vault, "A note to embed", "temporary-token")

    assert result.embedding == [0.4, 0.5, 0.6]
    assert result.user_id == @user
    assert result.dimensions == 3
    refute inspect(result) =~ "temporary-token"

    assert {:ok, %{deleted: true}} = Embeddings.delete_configuration(index, @user)
    assert Embeddings.get_configuration(index, @user) == {:error, :embedding_not_configured}
  end

  test "validates an existing configuration on demand", %{index: index} do
    configure(index)

    expect(OpenAI, :embed, fn _configuration, token, input ->
      assert token == "secret-provider-token"
      assert input =~ "Validate"

      {:ok, %{embedding: [0.1, 0.2], model: "text-embedding-3-small", usage: %{}}}
    end)

    assert {:ok, validation} = Embeddings.validate_configuration(index, @user)
    assert validation.status == "valid"
    assert validation.user_id == @user
    assert validation.dimensions == 2
  end

  test "stores nothing when the provider rejects the configuration", %{index: index} do
    expect(OpenAI, :embed, fn _configuration, _token, _input ->
      {:error, :embedding_provider_rejected}
    end)

    assert Embeddings.put_configuration(index, @user, %{
             "endpoint" => @endpoint,
             "model" => "text-embedding-3-small",
             "token" => "wrong-token"
           }) == {:error, :embedding_provider_rejected}

    assert Repo.get(Configuration, @user) == nil
  end

  test "leaves a working configuration in place when an update fails", %{index: index} do
    configure(index)

    expect(OpenAI, :embed, fn _configuration, _token, _input ->
      {:error, :embedding_provider_rejected}
    end)

    assert Embeddings.put_configuration(index, @user, %{
             "endpoint" => @endpoint,
             "model" => "a-model-that-does-not-exist",
             "token" => "secret-provider-token"
           }) == {:error, :embedding_provider_rejected}

    assert Repo.get!(Configuration, @user).model == "text-embedding-3-small"
  end

  test "refuses an endpoint that reaches a private address", %{index: index} do
    # No expectation is set, so the request never leaves the process.
    for endpoint <- [
          "http://localhost:8080/v1/embeddings",
          "https://127.0.0.1/v1/embeddings",
          "https://10.0.0.5/v1/embeddings",
          "https://169.254.169.254/latest/meta-data"
        ] do
      assert {:error, _reason} =
               Embeddings.put_configuration(index, @user, %{
                 "endpoint" => endpoint,
                 "model" => "text-embedding-3-small",
                 "token" => "secret-provider-token"
               })
    end

    assert Repo.get(Configuration, @user) == nil
  end

  test "requires a valid encryption key and valid embedding input", %{index: index} do
    index = %{index | embedding_secret_key: nil}

    assert Embeddings.put_configuration(index, @user, %{
             "endpoint" => @endpoint,
             "model" => "text-embedding-3-small",
             "token" => "token"
           }) == {:error, :embedding_secret_key_unavailable}

    assert Embeddings.embed(index, @vault, "") == {:error, :invalid_embedding_input}
  end

  test "rejects tampered or undecryptable provider credentials" do
    key = :crypto.strong_rand_bytes(32)
    assert {:ok, encrypted} = Secrets.encrypt("provider-token", key, "usr_test")

    tampered = Map.put(encrypted, :token_tag, :crypto.strong_rand_bytes(16))
    assert Secrets.decrypt(tampered, key, "usr_test") == {:error, :embedding_secret_invalid}

    assert Secrets.decrypt(encrypted, nil, "usr_test") ==
             {:error, :embedding_secret_key_unavailable}
  end

  # Regression tests for defects an adversarial review found in this change.

  test "refuses a vault-scoped call carrying an unrelated user_id", %{index: index} do
    index = %{index | embedding_client: StubClient}

    {:ok, victim} =
      Accounts.create_user(
        %{"id" => "review-victim", "email" => "victim@example.com"},
        index.repo
      )

    {:ok, victim_vault} =
      Accounts.create_vault(victim.id, %{"id" => "review-vault", "name" => "Victim"}, index.repo)

    {:ok, _configuration} =
      Embeddings.put_configuration(index, victim.id, %{
        "endpoint" => @endpoint,
        "model" => "victim-model",
        "token" => "victim-token"
      })

    # Authorization used to be chosen by the shape of the arguments, so adding a
    # user_id the caller does own made a vault-scoped call authorize against
    # that account and never check the vault. It would then embed with the
    # vault owner's credential.
    assert Operations.call(
             "embed_text",
             %{"vault_id" => victim_vault.id, "user_id" => @user, "input" => "private"},
             index,
             %{kind: :access_token, user_id: @user}
           ) == {:error, :forbidden}
  end

  test "refuses a token-omitting update whose credential changed underneath it", %{index: index} do
    index = %{index | embedding_client: StubClient}

    {:ok, _initial} =
      Embeddings.put_configuration(index, @user, %{
        "endpoint" => @endpoint,
        "model" => "initial",
        "token" => "old-token"
      })

    encoded_parent = self() |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)

    slow =
      Task.async(fn ->
        receive do
          :go ->
            Embeddings.put_configuration(index, @user, %{"model" => "slow:" <> encoded_parent})
        end
      end)

    Sandbox.allow(Repo, self(), slow.pid)
    send(slow.pid, :go)

    # The slow update has read the stored credential and is now mid-request.
    assert_receive {:slow_candidate_ready, slow_pid, "old-token"}

    assert {:ok, _fast} =
             Embeddings.put_configuration(index, @user, %{
               "model" => "fast",
               "token" => "new-token"
             })

    send(slow_pid, :release)

    # Storing this would pair the slow update's model with a credential it was
    # never validated against. Refusing keeps the promise that a stored
    # configuration is one that has been seen to work.
    assert Task.await(slow) == {:error, :embedding_configuration_changed}

    stored = Repo.get!(Configuration, @user)
    assert stored.model == "fast"
    assert {:ok, "new-token"} = Secrets.decrypt(stored, index.embedding_secret_key, @user)
  end

  test "does not resurrect a configuration deleted while an update was in flight", %{index: index} do
    index = %{index | embedding_client: StubClient}

    {:ok, _initial} =
      Embeddings.put_configuration(index, @user, %{
        "endpoint" => @endpoint,
        "model" => "initial",
        "token" => "old-token"
      })

    encoded_parent = self() |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)

    slow =
      Task.async(fn ->
        receive do
          :go ->
            Embeddings.put_configuration(index, @user, %{"model" => "slow:" <> encoded_parent})
        end
      end)

    Sandbox.allow(Repo, self(), slow.pid)
    send(slow.pid, :go)
    assert_receive {:slow_candidate_ready, slow_pid, "old-token"}

    # Revoking the credential has to be final. An upsert here would bring the
    # deleted row, and the credential it carried, straight back.
    assert {:ok, %{deleted: true}} = Embeddings.delete_configuration(index, @user)

    send(slow_pid, :release)
    assert Task.await(slow) == {:error, :embedding_configuration_changed}
    assert Repo.get(Configuration, @user) == nil
  end

  test "reports the stored timestamps rather than the ones a write proposed", %{index: index} do
    index = %{index | embedding_client: StubClient}

    {:ok, inserted} =
      Embeddings.put_configuration(index, @user, %{
        "endpoint" => @endpoint,
        "model" => "initial",
        "token" => "old-token"
      })

    row = Repo.get!(Configuration, @user)
    assert inserted.created_at == row.inserted_at

    assert {:ok, updated} = Embeddings.put_configuration(index, @user, %{"model" => "updated"})
    assert updated.created_at == row.inserted_at
    assert updated.updated_at == Repo.get!(Configuration, @user).updated_at
  end

  test "an update still has to satisfy the column rules", %{index: index} do
    index = %{index | embedding_client: StubClient}

    {:ok, _initial} =
      Embeddings.put_configuration(index, @user, %{
        "endpoint" => @endpoint,
        "model" => "initial",
        "token" => "old-token"
      })

    # The credential-omitting path writes through update_all, which walks past
    # the changeset unless it is asked first.
    assert {:error, %Ecto.Changeset{}} =
             Embeddings.put_configuration(index, @user, %{"model" => ""})

    assert Repo.get!(Configuration, @user).model == "initial"
  end

  test "refuses a partial write when no configuration exists", %{index: index} do
    index = %{index | embedding_client: StubClient}

    for attrs <- [
          %{},
          %{"endpoint" => @endpoint},
          %{"model" => "model"},
          %{"endpoint" => @endpoint, "model" => "model"},
          %{"endpoint" => @endpoint, "model" => "model", "token" => ""}
        ] do
      assert Embeddings.put_configuration(index, @user, attrs) == {:error, :invalid_arguments}
      assert Repo.get(Configuration, @user) == nil
    end
  end

  test "updates the model without resending the credential", %{index: index} do
    index = %{index | embedding_client: StubClient}

    {:ok, _initial} =
      Embeddings.put_configuration(index, @user, %{
        "endpoint" => @endpoint,
        "model" => "initial",
        "token" => "old-token"
      })

    assert {:ok, updated} =
             Operations.call(
               "configure_embedding",
               %{"user_id" => @user, "model" => "updated"},
               index
             )

    assert updated.model == "updated"
    assert updated.endpoint == @endpoint

    stored = Repo.get!(Configuration, @user)
    assert {:ok, "old-token"} = Secrets.decrypt(stored, index.embedding_secret_key, @user)
  end

  test "exercises a configured credential header before storing it", %{index: index} do
    expect(OpenAI, :embed, fn configuration, _token, _input ->
      # The candidate carries the header the stored row will carry, so the
      # request that decides whether to store is the request that will be made.
      assert configuration.credential_header == "x-bf-vk"
      {:ok, %{embedding: [0.1], model: "gateway-model", usage: %{}}}
    end)

    assert {:ok, configured} =
             Embeddings.put_configuration(index, @user, %{
               "endpoint" => @endpoint,
               "model" => "gateway-model",
               "credential_header" => "X-BF-VK",
               "token" => "virtual-key"
             })

    # One header, one spelling, whichever spelling arrived.
    assert configured.credential_header == "x-bf-vk"
    assert Repo.get!(Configuration, @user).credential_header == "x-bf-vk"
  end

  test "reports the default header for a configuration that never named one", %{index: index} do
    configure(index)

    assert {:ok, configuration} = Embeddings.get_configuration(index, @user)
    assert configuration.credential_header == "authorization"
    assert is_nil(Repo.get!(Configuration, @user).credential_header)
  end

  test "keeps the stored header when a later write leaves it out", %{index: index} do
    index = %{index | embedding_client: StubClient}

    {:ok, _initial} =
      Embeddings.put_configuration(index, @user, %{
        "endpoint" => @endpoint,
        "model" => "initial",
        "credential_header" => "x-bf-vk",
        "token" => "virtual-key"
      })

    assert {:ok, updated} =
             Embeddings.put_configuration(index, @user, %{"model" => "updated"})

    assert updated.model == "updated"
    assert updated.credential_header == "x-bf-vk"
  end

  test "goes back to a bearer token when a write names authorization", %{index: index} do
    index = %{index | embedding_client: StubClient}

    {:ok, _initial} =
      Embeddings.put_configuration(index, @user, %{
        "endpoint" => @endpoint,
        "model" => "gateway-model",
        "credential_header" => "x-bf-vk",
        "token" => "virtual-key"
      })

    assert {:ok, updated} =
             Embeddings.put_configuration(index, @user, %{"credential_header" => "authorization"})

    assert updated.credential_header == "authorization"

    assert Configuration.credential_header(Repo.get!(Configuration, @user), "virtual-key") ==
             {"authorization", "Bearer virtual-key"}
  end

  test "refuses a credential header the request writes itself", %{index: index} do
    # Nothing is asked of the provider, because the header never gets that far.
    for header <- ["content-type", "Accept", "host", "content-length"] do
      assert Embeddings.put_configuration(index, @user, %{
               "endpoint" => @endpoint,
               "model" => "text-embedding-3-small",
               "credential_header" => header,
               "token" => "virtual-key"
             }) == {:error, :invalid_arguments}
    end

    assert is_nil(Repo.get(Configuration, @user))
  end

  test "refuses a credential header that is not a header name", %{index: index} do
    malformed = [
      # A newline would end the header and start one of the caller's choosing.
      "x-bf-vk\r\nx-forwarded-for: 127.0.0.1",
      "x bf vk",
      ":authority",
      "",
      String.duplicate("x", 65),
      42
    ]

    for header <- malformed do
      assert Embeddings.put_configuration(index, @user, %{
               "endpoint" => @endpoint,
               "model" => "text-embedding-3-small",
               "credential_header" => header,
               "token" => "virtual-key"
             }) == {:error, :invalid_arguments}
    end

    assert is_nil(Repo.get(Configuration, @user))
  end

  defp configure(index) do
    expect(OpenAI, :embed, fn _configuration, _token, _input ->
      {:ok, %{embedding: [0.1, 0.2, 0.3], model: "text-embedding-3-small", usage: %{}}}
    end)

    {:ok, configuration} =
      Embeddings.put_configuration(index, @user, %{
        "endpoint" => @endpoint,
        "model" => "text-embedding-3-small",
        "dimensions" => 3,
        "token" => "secret-provider-token"
      })

    configuration
  end
end

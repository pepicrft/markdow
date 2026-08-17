defmodule Markdow.EmbeddingsTest do
  use Markdow.DataCase, async: true

  alias Markdow.Embeddings
  alias Markdow.Embeddings.Configuration
  alias Markdow.Embeddings.OpenAI
  alias Markdow.Repo
  alias Markdow.Secrets

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

defmodule Markdow.EmbeddingsTest do
  use Markdow.DataCase, async: true

  alias Markdow.Embeddings
  alias Markdow.Embeddings.Configuration
  alias Markdow.Embeddings.OpenAI
  alias Markdow.Repo
  alias Markdow.Secrets

  setup :verify_on_exit!

  test "encrypts a vault credential, validates it, embeds text, and redacts every response", %{
    index: index
  } do
    assert {:ok, configured} =
             Embeddings.put_configuration(index, "default", %{
               "provider" => "openai",
               "model" => "text-embedding-3-small",
               "dimensions" => 3,
               "token" => "secret-provider-token"
             })

    assert configured.credential_hint == "••••oken"
    refute inspect(configured) =~ "secret-provider-token"

    stored = Repo.get!(Configuration, "default")
    refute stored.token_ciphertext == "secret-provider-token"
    refute inspect(stored) =~ "secret-provider-token"

    expect(OpenAI, :embed, fn configuration, token, input ->
      assert configuration.vault_id == "default"
      assert token == "secret-provider-token"
      assert input =~ "Validate"

      {:ok,
       %{
         embedding: [0.1, 0.2, 0.3],
         model: "text-embedding-3-small",
         usage: %{"total_tokens" => 6}
       }}
    end)

    assert {:ok, validation} = Embeddings.validate_configuration(index, "default")
    assert validation.status == "valid"
    assert validation.dimensions == 3

    expect(OpenAI, :embed, fn configuration, token, input ->
      assert configuration.vault_id == "default"
      assert token == "temporary-token"
      assert input == "A note to embed"

      {:ok,
       %{
         embedding: [0.4, 0.5, 0.6],
         model: "text-embedding-3-small",
         usage: %{"total_tokens" => 4}
       }}
    end)

    assert {:ok, result} =
             Embeddings.embed(index, "default", "A note to embed", "temporary-token")

    assert result.embedding == [0.4, 0.5, 0.6]
    assert result.dimensions == 3
    refute inspect(result) =~ "temporary-token"

    assert {:ok, %{deleted: true}} = Embeddings.delete_configuration(index, "default")

    assert Embeddings.get_configuration(index, "default") ==
             {:error, :embedding_not_configured}
  end

  test "requires a valid encryption key and valid embedding input", %{index: index} do
    index = %{index | embedding_secret_key: nil}

    assert Embeddings.put_configuration(index, "default", %{"token" => "token"}) ==
             {:error, :embedding_secret_key_unavailable}

    assert Embeddings.embed(index, "default", "") == {:error, :invalid_embedding_input}
  end

  test "rejects tampered or undecryptable provider credentials" do
    key = :crypto.strong_rand_bytes(32)
    assert {:ok, encrypted} = Secrets.encrypt("provider-token", key, "vault")

    tampered = Map.put(encrypted, :token_tag, :crypto.strong_rand_bytes(16))
    assert Secrets.decrypt(tampered, key, "vault") == {:error, :embedding_secret_invalid}

    assert Secrets.decrypt(encrypted, nil, "vault") ==
             {:error, :embedding_secret_key_unavailable}
  end
end

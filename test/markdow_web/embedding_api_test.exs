defmodule MarkdowWeb.EmbeddingApiTest do
  use Markdow.DataCase, async: true

  alias Markdow.DataCase
  alias Markdow.Embeddings.OpenAI

  setup :verify_on_exit!

  # An address literal, so the endpoint policy never consults a name server.
  @endpoint "https://203.0.113.10/v1/embeddings"

  test "configures, validates, uses, and deletes a bring-your-own embedding credential", %{
    index: index
  } do
    # Configuring is not taken on trust: it embeds before it stores.
    expect(OpenAI, :embed, fn configuration, "provider-token", input ->
      assert configuration.endpoint == @endpoint
      assert input =~ "Validate"
      provider_result([0.1, 0.2, 0.3], 6)
    end)

    configured =
      index
      |> request(:put, "/users/local/embedding-configuration", %{
        "endpoint" => @endpoint,
        "model" => "text-embedding-3-small",
        "dimensions" => 3,
        "token" => "provider-token"
      })
      |> json_response(200)

    assert configured["user_id"] == "local"
    assert configured["endpoint"] == @endpoint
    assert configured["credential_hint"] == "••••oken"
    assert configured["validated_at"]
    refute JSON.encode!(configured) =~ "provider-token"

    expect(OpenAI, :embed, fn _configuration, "provider-token", input ->
      assert input =~ "Validate"
      provider_result([0.1, 0.2, 0.3], 6)
    end)

    validation =
      index
      |> request(:post, "/users/local/embedding-configuration/validate", %{})
      |> json_response(200)

    assert validation["status"] == "valid"
    assert validation["dimensions"] == 3

    expect(OpenAI, :embed, fn _configuration, "one-use-token", "Semantic text" ->
      provider_result([0.4, 0.5, 0.6], 3)
    end)

    # Embedding is still addressed by vault and resolves the owner's account.
    embedded =
      index
      |> request(:post, "/vaults/default/embeddings", %{
        "input" => "Semantic text",
        "token" => "one-use-token"
      })
      |> json_response(200)

    assert embedded["embedding"] == [0.4, 0.5, 0.6]
    assert embedded["user_id"] == "local"
    assert embedded["usage"] == %{"total_tokens" => 3}
    refute JSON.encode!(embedded) =~ "one-use-token"

    assert %{"deleted" => true, "user_id" => "local"} =
             index
             |> request(:delete, "/users/local/embedding-configuration", nil)
             |> json_response(200)

    assert request(index, :get, "/users/local/embedding-configuration", nil).status == 404
  end

  test "refuses an endpoint pointing at an internal address", %{index: index} do
    # No expectation, so a request reaching the provider would fail the test.
    response =
      request(index, :put, "/users/local/embedding-configuration", %{
        "endpoint" => "https://169.254.169.254/latest/meta-data",
        "model" => "text-embedding-3-small",
        "token" => "provider-token"
      })

    assert response.status == 422
    assert JSON.decode!(response.resp_body)["error"] == "embedding_endpoint_forbidden"
    assert request(index, :get, "/users/local/embedding-configuration", nil).status == 404
  end

  defp provider_result(embedding, tokens) do
    {:ok,
     %{
       embedding: embedding,
       model: "text-embedding-3-small",
       usage: %{"total_tokens" => tokens}
     }}
  end

  defp request(index, method, path, body) do
    DataCase.endpoint_conn(method, path, body, index, "test")
  end

  defp json_response(conn, status) do
    assert conn.status == status
    JSON.decode!(conn.resp_body)
  end
end

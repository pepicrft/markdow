defmodule MarkdowWeb.EmbeddingApiTest do
  use Markdow.DataCase, async: true

  alias Markdow.DataCase
  alias Markdow.Embeddings.OpenAI

  setup :verify_on_exit!

  test "configures, validates, uses, and deletes a bring-your-own embedding credential", %{
    index: index
  } do
    configured =
      index
      |> request(:put, "/vaults/default/embedding-configuration", %{
        "model" => "text-embedding-3-small",
        "dimensions" => 3,
        "token" => "provider-token"
      })
      |> json_response(200)

    assert configured["credential_hint"] == "••••oken"
    refute JSON.encode!(configured) =~ "provider-token"

    expect(OpenAI, :embed, fn _configuration, "provider-token", input ->
      assert input =~ "Validate"
      provider_result([0.1, 0.2, 0.3], 6)
    end)

    validation =
      index
      |> request(:post, "/vaults/default/embedding-configuration/validate", %{})
      |> json_response(200)

    assert validation["status"] == "valid"
    assert validation["dimensions"] == 3

    expect(OpenAI, :embed, fn _configuration, "one-use-token", "Semantic text" ->
      provider_result([0.4, 0.5, 0.6], 3)
    end)

    embedded =
      index
      |> request(:post, "/vaults/default/embeddings", %{
        "input" => "Semantic text",
        "token" => "one-use-token"
      })
      |> json_response(200)

    assert embedded["embedding"] == [0.4, 0.5, 0.6]
    assert embedded["usage"] == %{"total_tokens" => 3}
    refute JSON.encode!(embedded) =~ "one-use-token"

    assert %{"deleted" => true, "vault_id" => "default"} =
             index
             |> request(:delete, "/vaults/default/embedding-configuration", nil)
             |> json_response(200)

    assert request(index, :get, "/vaults/default/embedding-configuration", nil).status == 404
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

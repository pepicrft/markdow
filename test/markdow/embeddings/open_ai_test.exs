defmodule Markdow.Embeddings.OpenAITest do
  use ExUnit.Case, async: true
  use Mimic

  alias Markdow.Embeddings.Configuration
  alias Markdow.Embeddings.OpenAI

  setup :verify_on_exit!

  test "sends the configured model, dimensions, input, and bearer credential" do
    expect(Finch, :request, fn request, Markdow.Finch, options ->
      assert request.method == "POST"
      assert request.scheme == :https
      assert request.host == "api.openai.com"
      assert request.path == "/v1/embeddings"
      assert {"authorization", "Bearer provider-token"} in request.headers
      assert options == [receive_timeout: 30_000]

      payload = request.body |> IO.iodata_to_binary() |> JSON.decode!()

      assert payload == %{
               "model" => "text-embedding-3-small",
               "input" => "Text to embed",
               "encoding_format" => "float",
               "dimensions" => 3
             }

      {:ok,
       %Finch.Response{
         status: 200,
         body:
           JSON.encode!(%{
             data: [%{embedding: [0.1, 0.2, 0.3], index: 0, object: "embedding"}],
             model: "text-embedding-3-small",
             object: "list",
             usage: %{prompt_tokens: 3, total_tokens: 3}
           })
       }}
    end)

    configuration = %Configuration{
      user_id: "usr_test",
      endpoint: "https://api.openai.com/v1/embeddings",
      model: "text-embedding-3-small",
      dimensions: 3
    }

    assert {:ok, result} = OpenAI.embed(configuration, "provider-token", "Text to embed")
    assert result.embedding == [0.1, 0.2, 0.3]
    assert result.usage == %{"prompt_tokens" => 3, "total_tokens" => 3}
  end

  test "returns stable provider errors without exposing response contents" do
    expect(Finch, :request, fn _request, Markdow.Finch, _options ->
      {:ok, %Finch.Response{status: 401, body: ~s({"error":"secret provider detail"})}}
    end)

    configuration = %Configuration{
      endpoint: "https://api.openai.com/v1/embeddings",
      model: "text-embedding-3-small"
    }

    assert OpenAI.embed(configuration, "invalid-token", "Text") ==
             {:error, :embedding_provider_rejected}
  end

  test "sends to whichever endpoint the account configured" do
    expect(Finch, :request, fn request, Markdow.Finch, _options ->
      assert request.scheme == :https
      assert request.host == "gateway.example.com"
      assert request.path == "/v1/embeddings"

      # A gateway routing on a provider-qualified model takes it from the
      # configured model, untouched.
      payload = request.body |> IO.iodata_to_binary() |> JSON.decode!()
      assert payload["model"] == "fireworks/nomic-ai/nomic-embed-text-v1.5"

      {:ok,
       %Finch.Response{
         status: 200,
         body:
           JSON.encode!(%{
             data: [%{embedding: [0.5, 0.6], index: 0, object: "embedding"}],
             model: "fireworks/nomic-ai/nomic-embed-text-v1.5",
             object: "list",
             usage: %{prompt_tokens: 2, total_tokens: 2}
           })
       }}
    end)

    configuration = %Configuration{
      user_id: "usr_test",
      endpoint: "https://gateway.example.com/v1/embeddings",
      model: "fireworks/nomic-ai/nomic-embed-text-v1.5"
    }

    assert {:ok, result} = OpenAI.embed(configuration, "virtual-key", "Text to embed")
    assert result.embedding == [0.5, 0.6]
  end
end

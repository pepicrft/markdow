defmodule Markdow.Embeddings.OpenAITest do
  # The endpoint lives in application environment, which is global, so these
  # cannot run alongside other tests reading it.
  use ExUnit.Case, async: false
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
      vault_id: "default",
      provider: "openai",
      model: "text-embedding-3-small",
      dimensions: 3
    }

    assert {:ok, result} = OpenAI.embed(configuration, "provider-token", "Text to embed")
    assert result.embedding == [0.1, 0.2, 0.3]
    assert result.usage == %{"prompt_tokens" => 3, "total_tokens" => 3}
  end

  test "defaults to OpenAI when the deployment configures nothing" do
    put_endpoint(nil)

    assert OpenAI.endpoint() == "https://api.openai.com/v1/embeddings"
  end

  test "sends to the gateway the deployment configures, still as a bearer token" do
    put_endpoint("http://bifrost.bifrost.svc.cluster.local:8080/v1/embeddings")

    expect(Finch, :request, fn request, Markdow.Finch, _options ->
      assert request.scheme == :http
      assert request.host == "bifrost.bifrost.svc.cluster.local"
      assert request.port == 8080
      assert request.path == "/v1/embeddings"

      # Bifrost accepts the credential this way, so the gateway needs no
      # special header handling here.
      assert {"authorization", "Bearer virtual-key"} in request.headers

      # A gateway routes on a provider-qualified model, which comes from the
      # vault's configuration untouched.
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
      vault_id: "default",
      provider: "openai",
      model: "fireworks/nomic-ai/nomic-embed-text-v1.5"
    }

    assert {:ok, result} = OpenAI.embed(configuration, "virtual-key", "Text to embed")
    assert result.embedding == [0.5, 0.6]
  end

  test "returns stable provider errors without exposing response contents" do
    expect(Finch, :request, fn _request, Markdow.Finch, _options ->
      {:ok, %Finch.Response{status: 401, body: ~s({"error":"secret provider detail"})}}
    end)

    configuration = %Configuration{model: "text-embedding-3-small"}

    assert OpenAI.embed(configuration, "invalid-token", "Text") ==
             {:error, :embedding_provider_rejected}
  end

  # Restores whatever the environment had, deleting the key when it was unset
  # so the module default applies again rather than a stored nil.
  defp put_endpoint(value) do
    original = Application.fetch_env(:markdow, :embeddings_endpoint)

    on_exit(fn ->
      case original do
        {:ok, endpoint} -> Application.put_env(:markdow, :embeddings_endpoint, endpoint)
        :error -> Application.delete_env(:markdow, :embeddings_endpoint)
      end
    end)

    case value do
      nil -> Application.delete_env(:markdow, :embeddings_endpoint)
      endpoint -> Application.put_env(:markdow, :embeddings_endpoint, endpoint)
    end
  end
end

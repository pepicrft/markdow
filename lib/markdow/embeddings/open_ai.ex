defmodule Markdow.Embeddings.OpenAI do
  @moduledoc """
  Calls an embeddings application programming interface speaking the OpenAI
  protocol.

  The endpoint defaults to OpenAI and is overridden with
  `MARKDOW_EMBEDDINGS_ENDPOINT`, so a deployment can route embeddings through a
  gateway of its own. Gateways that expect a provider-qualified model name want
  that prefix in the vault's configured model rather than here.
  """

  @behaviour Markdow.Embeddings.Client

  @default_endpoint "https://api.openai.com/v1/embeddings"

  @doc "The endpoint embeddings are sent to."
  @spec endpoint() :: String.t()
  def endpoint, do: Application.get_env(:markdow, :embeddings_endpoint, @default_endpoint)

  @impl true
  def embed(configuration, token, input) do
    payload =
      %{model: configuration.model, input: input, encoding_format: "float"}
      |> maybe_dimensions(configuration.dimensions)

    request =
      Finch.build(
        :post,
        endpoint(),
        [
          {"authorization", "Bearer #{token}"},
          {"content-type", "application/json"},
          {"accept", "application/json"}
        ],
        JSON.encode!(payload)
      )

    case Finch.request(request, Markdow.Finch, receive_timeout: 30_000) do
      {:ok, %Finch.Response{status: status, body: body}} when status in 200..299 ->
        decode_embedding(body)

      {:ok, %Finch.Response{}} ->
        {:error, :embedding_provider_rejected}

      {:error, _reason} ->
        {:error, :embedding_provider_unavailable}
    end
  end

  defp decode_embedding(body) do
    case JSON.decode(body) do
      {:ok,
       %{
         "data" => [%{"embedding" => embedding} | _rest],
         "model" => model,
         "usage" => usage
       }}
      when is_list(embedding) ->
        if Enum.all?(embedding, &is_number/1) do
          {:ok, %{embedding: embedding, model: model, usage: usage}}
        else
          {:error, :embedding_provider_invalid_response}
        end

      _response ->
        {:error, :embedding_provider_invalid_response}
    end
  end

  defp maybe_dimensions(payload, nil), do: payload
  defp maybe_dimensions(payload, dimensions), do: Map.put(payload, :dimensions, dimensions)
end

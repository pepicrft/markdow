defmodule Markdow.Embeddings.OpenAI do
  @moduledoc """
  Calls an embeddings application programming interface speaking the OpenAI
  protocol.

  The address comes from the account's configuration, so each account reaches
  its own provider. A gateway that routes on a provider-qualified model wants
  that prefix in the configured model rather than here.
  """

  alias Markdow.Embeddings.Configuration
  alias Markdow.Embeddings.EndpointPolicy

  @behaviour Markdow.Embeddings.Client

  @receive_timeout 30_000
  @connect_timeout 5_000

  @impl true
  def embed(configuration, token, input) do
    payload =
      %{model: configuration.model, input: input, encoding_format: "float"}
      |> maybe_dimensions(configuration.dimensions)

    headers = [
      {"authorization", "Bearer #{token}"},
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    with {:ok, target} <- connection_target(configuration),
         {:ok, status, body} <- request(target, headers, JSON.encode!(payload)) do
      response(status, body)
    else
      {:error, _reason} -> {:error, :embedding_provider_unavailable}
    end
  end

  defp connection_target(%Configuration{connection_target: %{uri: %URI{}} = target}),
    do: {:ok, target}

  defp connection_target(%Configuration{endpoint: endpoint}),
    do: EndpointPolicy.resolve_endpoint(endpoint)

  # Operator-approved hosts may deliberately use a private name or plain text
  # transport. That exemption is a deployment decision, so its normal named
  # connection is preserved. Every account-supplied public endpoint connects
  # directly to a checked address instead.
  defp request(%{uri: uri, addresses: :operator_allowed}, headers, body) do
    request = Finch.build(:post, URI.to_string(uri), headers, body)

    case Finch.request(request, Markdow.Finch, receive_timeout: @receive_timeout) do
      {:ok, %Finch.Response{status: status, body: response_body}} -> {:ok, status, response_body}
      {:error, _reason} -> {:error, :embedding_provider_unavailable}
    end
  end

  defp request(%{uri: uri, addresses: addresses}, headers, body) when is_list(addresses) do
    Enum.reduce_while(addresses, {:error, :embedding_provider_unavailable}, fn address, _result ->
      case request_address(uri, address, headers, body) do
        {:ok, _status, _response_body} = result -> {:halt, result}
        {:error, _reason} -> {:cont, {:error, :embedding_provider_unavailable}}
      end
    end)
  end

  defp request_address(uri, address, headers, body) do
    options = [
      hostname: uri.host,
      transport_opts: [
        cacerts: :public_key.cacerts_get(),
        versions: [:"tlsv1.2", :"tlsv1.3"],
        timeout: @connect_timeout
      ]
    ]

    case Mint.HTTP.connect(:https, address, port(uri), options) do
      {:ok, connection} ->
        {result, connection} =
          case Mint.HTTP.request(connection, "POST", request_path(uri), headers, body) do
            {:ok, connection, reference} ->
              receive_response(connection, reference)

            {:error, connection, _reason} ->
              {{:error, :embedding_provider_unavailable}, connection}
          end

        Mint.HTTP.close(connection)
        result

      {:error, _reason} ->
        {:error, :embedding_provider_unavailable}
    end
  end

  defp receive_response(connection, reference, response \\ %{status: nil, body: []}) do
    receive do
      message ->
        case Mint.HTTP.stream(connection, message) do
          :unknown ->
            receive_response(connection, reference, response)

          {:ok, connection, responses} ->
            case consume_responses(responses, reference, response) do
              {:continue, response} ->
                receive_response(connection, reference, response)

              {:done, %{status: status, body: body}} when is_integer(status) ->
                {{:ok, status, body |> Enum.reverse() |> IO.iodata_to_binary()}, connection}

              _result ->
                {{:error, :embedding_provider_unavailable}, connection}
            end

          {:error, connection, _reason, _responses} ->
            {{:error, :embedding_provider_unavailable}, connection}
        end
    after
      @receive_timeout -> {{:error, :embedding_provider_unavailable}, connection}
    end
  end

  defp consume_responses(responses, reference, response) do
    Enum.reduce_while(responses, {:continue, response}, fn
      {:status, ^reference, status}, {:continue, response} ->
        {:cont, {:continue, %{response | status: status}}}

      {:data, ^reference, data}, {:continue, response} ->
        {:cont, {:continue, %{response | body: [data | response.body]}}}

      {:done, ^reference}, {:continue, response} ->
        {:halt, {:done, response}}

      {:error, ^reference, _reason}, _response ->
        {:halt, {:error, :embedding_provider_unavailable}}

      _other_response, accumulator ->
        {:cont, accumulator}
    end)
  end

  defp response(status, body) when status in 200..299, do: decode_embedding(body)
  defp response(_status, _body), do: {:error, :embedding_provider_rejected}

  defp request_path(%URI{path: nil, query: nil}), do: "/"
  defp request_path(%URI{path: nil, query: query}), do: "/?#{query}"
  defp request_path(%URI{path: path, query: nil}), do: path
  defp request_path(%URI{path: path, query: query}), do: "#{path}?#{query}"

  defp port(%URI{port: nil}), do: 443
  defp port(%URI{port: port}), do: port

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

defmodule MarkdowWeb.OpenGraph.Signer do
  @moduledoc """
  Signs and verifies the query parameters carried by Open Graph image URLs.

  Every image URL Markdow renders into a page carries a `sig` parameter: a
  keyed-hash message authentication code (see
  [RFC 2104](https://www.rfc-editor.org/rfc/rfc2104)) over the remaining
  parameters. The image endpoint only renders requests that Markdow itself
  minted, which closes the denial-of-service vector where anyone could trigger
  expensive headless-browser renders with arbitrary parameters.

  Signatures carry no timestamp, so the URLs stay cacheable and remain valid
  when a social crawler fetches them long after the page was served.
  """

  alias Plug.Crypto.KeyGenerator

  @salt "markdow-og-image"

  @doc "Returns the signature for the given parameter map."
  @spec sign(map(), binary()) :: String.t()
  def sign(params, secret) when is_map(params) and is_binary(secret) do
    :hmac
    |> :crypto.mac(:sha256, derive_key(secret), canonical(params))
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Verifies a signature against the given parameters with a constant-time compare.

  The `sig` key is ignored when present in `params`, so an incoming query map
  can be passed straight through.
  """
  @spec valid?(map(), term(), binary()) :: boolean()
  def valid?(params, signature, secret)
      when is_map(params) and is_binary(signature) and is_binary(secret) do
    expected = sign(Map.delete(params, "sig"), secret)
    Plug.Crypto.secure_compare(expected, signature)
  end

  def valid?(_params, _signature, _secret), do: false

  defp canonical(params) do
    params
    |> Map.delete("sig")
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp derive_key(secret), do: KeyGenerator.generate(secret, @salt)
end

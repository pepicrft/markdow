defmodule Markdow.Embeddings.EndpointPolicy do
  @moduledoc """
  Decides whether Markdow is willing to send an embedding request to an address.

  Accounts supply their own endpoint, so without a policy any signed-up user
  could aim the server at addresses only the server can reach and read the
  replies. Anything that resolves to a loopback, link-local, or private range is
  refused, which covers cluster services, cloud instance metadata, and the host
  itself.

  An operator can name hosts that are allowed anyway through
  `MARKDOW_EMBEDDINGS_ALLOWED_HOSTS`, which is how a deployment permits an
  internal gateway it runs on purpose.

  The check runs before every outbound request rather than only when a
  configuration is saved, because the name a configuration holds can be pointed
  somewhere else afterwards.
  """

  @type result :: {:ok, URI.t()} | {:error, atom()}

  @doc "Checks a configured endpoint, resolving its host to see where it leads."
  @spec check(String.t() | nil) :: result()
  def check(endpoint) when is_binary(endpoint) do
    with {:ok, uri} <- parse(endpoint),
         :ok <- check_scheme(uri),
         :ok <- check_host(uri) do
      {:ok, uri}
    end
  end

  def check(_endpoint), do: {:error, :embedding_endpoint_invalid}

  @doc "The hosts an operator has exempted from the address rules."
  @spec allowed_hosts() :: [String.t()]
  def allowed_hosts do
    :markdow
    |> Application.get_env(:embeddings_allowed_hosts, [])
    |> List.wrap()
    |> Enum.map(&String.downcase/1)
  end

  defp parse(endpoint) do
    case URI.new(endpoint) do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when is_binary(scheme) and is_binary(host) and host != "" ->
        {:ok, uri}

      _invalid ->
        {:error, :embedding_endpoint_invalid}
    end
  end

  # Plain text would put the credential on the wire in readable form. An
  # operator naming a host takes responsibility for how it is reached.
  defp check_scheme(%URI{scheme: "https"}), do: :ok

  defp check_scheme(%URI{scheme: "http"} = uri) do
    if allowed_host?(uri), do: :ok, else: {:error, :embedding_endpoint_insecure}
  end

  defp check_scheme(_uri), do: {:error, :embedding_endpoint_invalid}

  defp check_host(%URI{} = uri) do
    if allowed_host?(uri) do
      :ok
    else
      case resolve(uri.host) do
        {:ok, addresses} ->
          if Enum.all?(addresses, &public_address?/1),
            do: :ok,
            else: {:error, :embedding_endpoint_forbidden}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp allowed_host?(%URI{host: host}) when is_binary(host),
    do: String.downcase(host) in allowed_hosts()

  defp allowed_host?(_uri), do: false

  # Every address the name resolves to has to be acceptable. A name answering
  # with one public and one private address would otherwise be a way through.
  defp resolve(host) do
    charlist = String.to_charlist(host)

    results =
      [:inet, :inet6]
      |> Enum.map(&:inet.getaddrs(charlist, &1))
      |> Enum.flat_map(fn
        {:ok, addresses} -> addresses
        {:error, _reason} -> []
      end)

    case results do
      [] -> {:error, :embedding_endpoint_unresolvable}
      addresses -> {:ok, addresses}
    end
  end

  # Loopback, private, link-local, carrier-grade NAT, and the metadata address
  # every cloud puts on 169.254.169.254.
  defp public_address?({127, _b, _c, _d}), do: false
  defp public_address?({10, _b, _c, _d}), do: false
  defp public_address?({192, 168, _c, _d}), do: false
  defp public_address?({169, 254, _c, _d}), do: false
  defp public_address?({172, b, _c, _d}) when b >= 16 and b <= 31, do: false
  defp public_address?({100, b, _c, _d}) when b >= 64 and b <= 127, do: false
  defp public_address?({0, _b, _c, _d}), do: false
  # Protocol assignments, the deprecated 6to4 relay anycast address, and the
  # benchmarking range, none of which name a host anyone should be reaching.
  defp public_address?({192, 0, 0, _d}), do: false
  defp public_address?({192, 88, 99, _d}), do: false
  defp public_address?({198, b, _c, _d}) when b in [18, 19], do: false
  defp public_address?({a, _b, _c, _d}) when a >= 224, do: false
  defp public_address?({_a, _b, _c, _d}), do: true

  # IPv6 loopback, unspecified, unique local, link local, site local, the
  # discard-only prefix, and multicast.
  defp public_address?({0, 0, 0, 0, 0, 0, 0, 1}), do: false
  defp public_address?({0, 0, 0, 0, 0, 0, 0, 0}), do: false
  defp public_address?({0x0100, 0, 0, 0, _e, _f, _g, _h}), do: false

  defp public_address?({a, _b, _c, _d, _e, _f, _g, _h}) when a >= 0xFC00 and a <= 0xFDFF,
    do: false

  defp public_address?({a, _b, _c, _d, _e, _f, _g, _h}) when a >= 0xFE80 and a <= 0xFEFF,
    do: false

  defp public_address?({a, _b, _c, _d, _e, _f, _g, _h}) when a >= 0xFF00, do: false

  # Every IPv6 form that carries an IPv4 address is judged on the address it
  # carries, so loopback cannot be smuggled through in IPv6 clothing. The
  # mapped form is the one a Linux host actually routes to IPv4; the
  # compatible, translated, NAT64, and 6to4 forms are deprecated or need a
  # relay, but a deny list has no business leaving them to a catch-all that
  # answers "public".
  defp public_address?({0, 0, 0, 0, 0, 0xFFFF, g, h}), do: public_address?(embedded_v4(g, h))
  defp public_address?({0, 0, 0, 0, 0xFFFF, 0, g, h}), do: public_address?(embedded_v4(g, h))
  defp public_address?({0x64, 0xFF9B, 0, 0, 0, 0, g, h}), do: public_address?(embedded_v4(g, h))

  defp public_address?({0x64, 0xFF9B, 1, _d, _e, _f, g, h}),
    do: public_address?(embedded_v4(g, h))

  defp public_address?({0x2002, g, h, _d, _e, _f, _g, _h}), do: public_address?(embedded_v4(g, h))

  # Anything else in ::/96 is the deprecated IPv4-compatible form. The
  # unspecified and loopback addresses were already answered above.
  defp public_address?({0, 0, 0, 0, 0, 0, g, h}), do: public_address?(embedded_v4(g, h))

  defp public_address?({_a, _b, _c, _d, _e, _f, _g, _h}), do: true

  defp public_address?(_address), do: false

  defp embedded_v4(g, h), do: {div(g, 256), rem(g, 256), div(h, 256), rem(h, 256)}
end

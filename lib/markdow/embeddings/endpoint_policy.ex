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

  @type address :: :inet.ip_address()
  @type target :: %{uri: URI.t(), addresses: [address()] | :operator_allowed}
  @type result :: {:ok, URI.t()} | {:error, atom()}

  @doc "Checks a configured endpoint, resolving its host to see where it leads."
  @spec check(String.t() | nil, keyword()) :: result()
  def check(endpoint, opts \\ [])

  def check(endpoint, opts) when is_binary(endpoint) do
    with {:ok, %{uri: uri}} <- resolve_endpoint(endpoint, opts) do
      {:ok, uri}
    end
  end

  def check(_endpoint, _opts), do: {:error, :embedding_endpoint_invalid}

  @doc """
  Resolves an endpoint into the exact addresses a request may use.

  The caller must connect to one of these returned addresses rather than
  resolving the hostname again. That makes validation and connection one
  operation, preventing a hostname from being changed to a private address in
  the interval between the two.
  """
  @spec resolve_endpoint(String.t() | nil, keyword()) :: {:ok, target()} | {:error, atom()}
  def resolve_endpoint(endpoint, opts \\ [])

  def resolve_endpoint(endpoint, opts) when is_binary(endpoint) do
    with {:ok, uri} <- parse(endpoint),
         :ok <- check_scheme(uri, opts) do
      resolve_host(uri, opts)
    end
  end

  def resolve_endpoint(_endpoint, _opts), do: {:error, :embedding_endpoint_invalid}

  @doc "The hosts an operator has exempted from the address rules."
  @spec allowed_hosts(keyword()) :: [String.t()]
  def allowed_hosts(opts \\ []) do
    opts
    |> Keyword.get(:allowed_hosts, Application.get_env(:markdow, :embeddings_allowed_hosts, []))
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
  defp check_scheme(%URI{scheme: "https"}, _opts), do: :ok

  defp check_scheme(%URI{scheme: "http"} = uri, opts) do
    if allowed_host?(uri, opts), do: :ok, else: {:error, :embedding_endpoint_insecure}
  end

  defp check_scheme(_uri, _opts), do: {:error, :embedding_endpoint_invalid}

  defp resolve_host(%URI{} = uri, opts) do
    if allowed_host?(uri, opts) do
      {:ok, %{uri: uri, addresses: :operator_allowed}}
    else
      resolve_public_host(uri, opts)
    end
  end

  defp resolve_public_host(uri, opts) do
    with {:ok, addresses} <- resolve(uri.host, opts) do
      target_for_public_addresses(uri, addresses)
    end
  end

  defp target_for_public_addresses(uri, addresses) do
    if Enum.all?(addresses, &public_address?/1),
      do: {:ok, %{uri: uri, addresses: addresses}},
      else: {:error, :embedding_endpoint_forbidden}
  end

  defp allowed_host?(%URI{host: host}, opts) when is_binary(host),
    do: String.downcase(host) in allowed_hosts(opts)

  defp allowed_host?(_uri, _opts), do: false

  # Every address the name resolves to has to be acceptable. A name answering
  # with one public and one private address would otherwise be a way through.
  defp resolve(host, opts) do
    resolver = Keyword.get(opts, :resolver, &system_resolve/1)

    case resolver.(host) do
      {:ok, addresses} when is_list(addresses) and addresses != [] -> {:ok, Enum.uniq(addresses)}
      _result -> {:error, :embedding_endpoint_unresolvable}
    end
  end

  defp system_resolve(host) do
    charlist = String.to_charlist(host)

    results =
      [:inet, :inet6]
      |> Enum.map(&:inet.getaddrs(charlist, &1))
      |> Enum.flat_map(fn
        {:ok, addresses} -> addresses
        {:error, _reason} -> []
      end)

    {:ok, results}
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

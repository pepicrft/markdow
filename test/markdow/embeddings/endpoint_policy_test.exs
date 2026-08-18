defmodule Markdow.Embeddings.EndpointPolicyTest do
  # The allow-list lives in application environment, which is global.
  use ExUnit.Case, async: false

  alias Markdow.Embeddings.EndpointPolicy

  # Address literals throughout, so nothing here depends on a name server.
  # 203.0.113.0/24 is the documentation range and counts as public.
  @public "https://203.0.113.10/v1/embeddings"

  setup do
    original = Application.fetch_env(:markdow, :embeddings_allowed_hosts)

    on_exit(fn ->
      case original do
        {:ok, hosts} -> Application.put_env(:markdow, :embeddings_allowed_hosts, hosts)
        :error -> Application.delete_env(:markdow, :embeddings_allowed_hosts)
      end
    end)

    Application.delete_env(:markdow, :embeddings_allowed_hosts)
    :ok
  end

  test "accepts a public https endpoint" do
    assert {:ok, %URI{}} = EndpointPolicy.check(@public)
  end

  test "refuses addresses only the server can reach" do
    for endpoint <- [
          "https://127.0.0.1/v1/embeddings",
          "https://10.1.2.3/v1/embeddings",
          "https://192.168.1.1/v1/embeddings",
          "https://172.16.0.1/v1/embeddings",
          "https://172.31.255.255/v1/embeddings",
          "https://100.64.0.1/v1/embeddings",
          "https://0.0.0.0/v1/embeddings",
          "https://[::1]/v1/embeddings",
          "https://[fd00::1]/v1/embeddings",
          "https://[fe80::1]/v1/embeddings"
        ] do
      assert EndpointPolicy.check(endpoint) == {:error, :embedding_endpoint_forbidden},
             "expected #{endpoint} to be refused"
    end
  end

  test "refuses the cloud instance metadata address" do
    assert EndpointPolicy.check("https://169.254.169.254/latest/meta-data") ==
             {:error, :embedding_endpoint_forbidden}
  end

  test "refuses an IPv4 address smuggled inside an IPv6 one" do
    assert EndpointPolicy.check("https://[::ffff:127.0.0.1]/v1/embeddings") ==
             {:error, :embedding_endpoint_forbidden}

    assert EndpointPolicy.check("https://[::ffff:169.254.169.254]/v1/embeddings") ==
             {:error, :embedding_endpoint_forbidden}
  end

  test "refuses plain text, which would put the credential on the wire" do
    assert EndpointPolicy.check("http://203.0.113.10/v1/embeddings") ==
             {:error, :embedding_endpoint_insecure}
  end

  test "refuses anything that is not a usable address" do
    for endpoint <- ["", "not a url", "ftp://203.0.113.10/x", "https://", "/v1/embeddings"] do
      assert {:error, _reason} = EndpointPolicy.check(endpoint),
             "expected #{inspect(endpoint)} to be refused"
    end

    assert EndpointPolicy.check(nil) == {:error, :embedding_endpoint_invalid}
  end

  test "lets an operator exempt a host it runs itself" do
    Application.put_env(:markdow, :embeddings_allowed_hosts, ["bifrost.bifrost.svc.cluster.local"])

    # Exempt by name, including over plain text inside a trusted network.
    assert {:ok, %URI{}} =
             EndpointPolicy.check("http://bifrost.bifrost.svc.cluster.local:8080/v1/embeddings")

    # The exemption is for that host only, not for private addresses at large.
    assert EndpointPolicy.check("https://10.0.0.5/v1/embeddings") ==
             {:error, :embedding_endpoint_forbidden}
  end

  test "matches an exempted host regardless of letter case" do
    Application.put_env(:markdow, :embeddings_allowed_hosts, ["Gateway.Internal"])

    assert {:ok, %URI{}} = EndpointPolicy.check("https://gateway.internal/v1/embeddings")
  end

  test "refuses loopback written as an integer, in octal, and in hexadecimal" do
    # The host is resolved before it is judged, so these normalise to 127.0.0.1
    # rather than being read as names.
    #
    # The reason is deliberately not asserted. Which spellings a resolver
    # accepts is platform dependent: the deployment image reads all four as
    # loopback and refuses them as forbidden, while a resolver that does not
    # parse the hexadecimal form refuses it as unresolvable instead. Either way
    # the endpoint is refused, and a host the policy cannot resolve is a host
    # the client cannot connect to, since both go through the same resolver.
    for host <- ["2130706433", "0177.0.0.1", "0x7f000001", "127.1"] do
      assert {:error, _reason} = EndpointPolicy.check("https://#{host}/v1/embeddings"),
             "expected #{host} to be refused"
    end
  end

  test "judges the host and not the credentials in front of it" do
    assert EndpointPolicy.check("https://public.example@127.0.0.1/v1/embeddings") ==
             {:error, :embedding_endpoint_forbidden}
  end

  test "refuses every IPv6 form that carries an internal IPv4 address" do
    for host <- [
          # Mapped, the form a Linux host routes straight to IPv4.
          "::ffff:127.0.0.1",
          "::ffff:169.254.169.254",
          "::ffff:10.0.0.1",
          # Compatible, translated, NAT64, and 6to4, which used to reach the
          # catch-all and be answered "public".
          "::127.0.0.1",
          "::ffff:0:127.0.0.1",
          "64:ff9b::127.0.0.1",
          "64:ff9b:1::169.254.169.254",
          "2002:7f00:1::"
        ] do
      assert EndpointPolicy.check("https://[#{host}]/v1/embeddings") ==
               {:error, :embedding_endpoint_forbidden},
             "expected #{host} to be refused"
    end
  end

  test "refuses the IPv6 ranges that are not for reaching anyone" do
    for host <- ["::1", "::", "fe80::1", "fec0::1", "fd00::1", "100::1", "ff02::1"] do
      assert EndpointPolicy.check("https://[#{host}]/v1/embeddings") ==
               {:error, :embedding_endpoint_forbidden},
             "expected #{host} to be refused"
    end
  end

  test "refuses the reserved IPv4 ranges that are not private but are not hosts either" do
    for host <- ["192.0.0.170", "192.88.99.1", "198.18.0.1", "198.19.255.1", "240.0.0.1"] do
      assert EndpointPolicy.check("https://#{host}/v1/embeddings") ==
               {:error, :embedding_endpoint_forbidden},
             "expected #{host} to be refused"
    end
  end

  test "still allows an ordinary public address over both protocols" do
    assert {:ok, %URI{}} = EndpointPolicy.check("https://203.0.113.10/v1/embeddings")
    assert {:ok, %URI{}} = EndpointPolicy.check("https://[2606:4700::1111]/v1/embeddings")
  end
end

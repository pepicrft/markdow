defmodule MarkdowWeb.OpenGraphTest do
  use ExUnit.Case, async: true
  use Mimic

  import Plug.Conn

  alias MarkdowWeb.LegalPage
  alias MarkdowWeb.OpenGraph
  alias MarkdowWeb.OpenGraph.Cache
  alias MarkdowWeb.OpenGraph.Card
  alias MarkdowWeb.OpenGraph.Signer

  setup :verify_on_exit!

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "markdow-og-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf(directory) end)

    {:ok, config: [enabled: true, cache_dir: directory], directory: directory}
  end

  test "the marketing pages advertise a signed social card", %{config: config} do
    for {path, expected_title} <- [
          {"/", "A semantic layer for your Markdown."},
          {"/terms", "Terms of service"},
          {"/privacy", "Privacy policy"},
          {"/cookies", "Cookie terms"}
        ] do
      body = path |> request(config) |> Map.fetch!(:resp_body)

      assert body =~ ~s(<meta name="twitter:card" content="summary_large_image">)
      assert body =~ ~s(<meta property="og:image:width" content="1200">)
      assert body =~ ~s(<meta property="og:image:height" content="630">)

      query =
        body |> advertised_image() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert Map.has_key?(query, "sig")
      # The advertised URL names the card that page renders.
      assert {:ok, page} = Card.parse(query["page"])
      assert Card.html(page) =~ expected_title
    end
  end

  test "omits the card when the instance cannot render one" do
    body = "/" |> request(enabled: false) |> Map.fetch!(:resp_body)

    refute body =~ "og:image"
    refute body =~ "twitter:card"
  end

  test "renders a card once and serves it from the cache afterwards", %{config: config} do
    expect(Carta, :render, 1, fn _pool, html, opts ->
      assert html =~ "A semantic layer for your Markdown."
      assert opts[:width] == 1200
      assert opts[:height] == 630

      {:ok, "rendered-jpeg"}
    end)

    path = OpenGraph.image_url(:home, "", config)
    first = request(path, config)

    assert first.status == 200
    assert get_resp_header(first, "content-type") == ["image/jpeg"]
    assert get_resp_header(first, "cache-control") == ["public, max-age=31536000, immutable"]
    assert first.resp_body == "rendered-jpeg"

    # The second request is served from disk: Carta is expected exactly once.
    assert path |> request(config) |> Map.fetch!(:resp_body) == "rendered-jpeg"
  end

  test "refuses to render a request that Markdow did not sign", %{config: config} do
    reject(&Carta.render/3)

    tampered =
      :home
      |> OpenGraph.image_url("", config)
      |> String.replace(~r/sig=[^&]*/, "sig=forged")

    response = request(tampered, config)

    assert response.status == 403
    assert response.resp_body == "Invalid signature"
  end

  test "reports an unknown page as missing rather than rendering it", %{config: config} do
    reject(&Carta.render/3)

    params = %{"page" => "pricing", "v" => "0"}
    query = params |> Map.put("sig", Signer.sign(params, secret())) |> URI.encode_query()

    assert ("/og-image?" <> query) |> request(config) |> Map.fetch!(:status) == 404
  end

  test "reports a render failure without caching it", %{config: config, directory: directory} do
    expect(Carta, :render, fn _pool, _html, _opts -> {:error, :browser_unavailable} end)

    response = :home |> OpenGraph.image_url("", config) |> request(config)

    assert response.status == 503
    assert response.resp_body == "The image could not be rendered"

    assert Cache.get(directory, OpenGraph.cache_key(Card.html(:home))) == {:error, :not_found}
  end

  test "the card reads its copy from the page it represents" do
    %{title: title, introduction: introduction} = LegalPage.metadata(:privacy)
    card = Card.html(:privacy)

    assert card =~ title
    assert card =~ introduction
    assert Card.pages() == [:home, :terms, :privacy, :cookies]
    assert Card.parse("privacy") == {:ok, :privacy}
    assert Card.parse("elsewhere") == :error
  end

  defp request(path, config) do
    :get
    |> Plug.Test.conn(path)
    |> put_private(:markdow_open_graph, config)
    |> put_req_header("accept", "text/html")
    |> MarkdowWeb.Endpoint.call([])
  end

  defp advertised_image(body) do
    [_match, url] = Regex.run(~r/<meta property="og:image" content="([^"]+)">/, body)

    String.replace(url, "&amp;", "&")
  end

  defp secret do
    :markdow
    |> Application.fetch_env!(MarkdowWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end
end

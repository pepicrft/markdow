defmodule MarkdowWeb.OpenGraph do
  @moduledoc """
  Generates and serves the social preview images for the marketing pages.

  A card is rendered by a headless browser pool
  ([Carta](https://github.com/pepicrft/carta)) the first time it is requested,
  cached on the instance's data volume under a key derived from the rendered
  document, and served from that cache afterwards. Nothing is rendered at build
  time, and nothing needs invalidating: new copy or a new palette produces a new
  key.

  Every URL minted here carries a signature verified by
  `MarkdowWeb.OpenGraph.Signer`, so the endpoint only renders requests Markdow
  itself produced.

  An instance without a browser pool (`MARKDOW_OG_BROWSER_POOL_SIZE=0`) turns
  the feature off: pages omit the image tags and the endpoint reports the image
  as unavailable rather than pointing crawlers at a broken URL.

  Callers pass the configuration in. `configuration/1` resolves it from the
  connection, which lets a request or a test supply its own without touching
  application state.
  """

  alias MarkdowWeb.OpenGraph.Cache
  alias MarkdowWeb.OpenGraph.Card
  alias MarkdowWeb.OpenGraph.Signer

  @pool MarkdowWeb.OpenGraph.BrowserPool
  @render_opts [width: 1200, height: 630, quality: 90]
  @path "/og-image"

  @typedoc "Whether cards are rendered, and where the rendered bytes live."
  @type configuration :: keyword()

  @doc "The Open Graph configuration for a request."
  @spec configuration(Plug.Conn.t()) :: configuration()
  def configuration(conn) do
    conn.private[:markdow_open_graph] || Application.get_env(:markdow, :open_graph, [])
  end

  @doc "Whether this instance can render social cards."
  @spec enabled?(configuration()) :: boolean()
  def enabled?(config), do: Keyword.get(config, :enabled, false)

  @doc "The directory rendered cards are cached in."
  @spec cache_directory(configuration()) :: String.t()
  def cache_directory(config) do
    Keyword.get_lazy(config, :cache_dir, fn ->
      :markdow |> Application.fetch_env!(:data_dir) |> Path.expand() |> Path.join("og")
    end)
  end

  @doc """
  The absolute, signed image URL for a page, or `nil` when rendering is off.
  """
  @spec image_url(Card.page(), String.t(), configuration()) :: String.t() | nil
  def image_url(page, base_url, config) do
    if enabled?(config) do
      params = %{"page" => Atom.to_string(page), "v" => version(page)}
      query = params |> Map.put("sig", Signer.sign(params, secret())) |> URI.encode_query()

      base_url <> @path <> "?" <> query
    end
  end

  @doc """
  The `<head>` markup advertising a page's social card.

  Returns an empty string when rendering is off, so a page stays valid without a
  conditional at every call site.
  """
  @spec meta_tags(Card.page(), String.t(), configuration()) :: String.t()
  def meta_tags(page, base_url, config) do
    case image_url(page, base_url, config) do
      nil ->
        ""

      url ->
        {width, height} = Card.dimensions()

        """
        <meta property="og:image" content="#{escape(url)}">
        <meta property="og:image:width" content="#{width}">
        <meta property="og:image:height" content="#{height}">
        <meta name="twitter:card" content="summary_large_image">
        """
    end
  end

  @doc "Verifies the signature carried by an incoming image request."
  @spec verify_signature(map()) :: boolean()
  def verify_signature(params) when is_map(params),
    do: Signer.valid?(params, Map.get(params, "sig"), secret())

  @doc """
  Returns the image for the requested page, rendering it if it is not cached.
  """
  @spec render(map(), configuration()) ::
          {:ok, binary()} | {:error, :not_found | :disabled | term()}
  def render(params, config)

  def render(%{"page" => name}, config) when is_binary(name) do
    if enabled?(config) do
      case Card.parse(name) do
        {:ok, page} -> page |> Card.html() |> fetch_or_render(cache_directory(config))
        :error -> {:error, :not_found}
      end
    else
      {:error, :disabled}
    end
  end

  def render(_params, _config), do: {:error, :not_found}

  @doc "The cache key for a rendered card, derived from its document."
  @spec cache_key(String.t()) :: String.t()
  def cache_key(html), do: Carta.cache_key(html, @render_opts) <> ".jpg"

  # The version binds the URL, and therefore its signature, to the card that
  # will be rendered, so a crawler refetches after a copy or palette change.
  defp version(page) do
    page
    |> Card.html()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 12)
  end

  defp fetch_or_render(html, directory) do
    key = cache_key(html)

    case Cache.get(directory, key) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, :not_found} -> render_locked(html, directory, key)
      {:error, _reason} = error -> error
    end
  end

  # The render is guarded by a lock keyed on the cache entry, so a burst of
  # first hits renders the card once instead of each request launching a
  # browser.
  defp render_locked(html, directory, key) do
    with_lock(key, fn ->
      # Another request may have finished while this one waited for the lock.
      case Cache.get(directory, key) do
        {:ok, bytes} -> {:ok, bytes}
        {:error, :not_found} -> render_and_store(html, directory, key)
        {:error, _reason} = error -> error
      end
    end)
  end

  defp render_and_store(html, directory, key) do
    with {:ok, jpeg} <- Carta.render(@pool, html, @render_opts),
         :ok <- Cache.put(directory, key, jpeg) do
      {:ok, jpeg}
    end
  end

  defp with_lock(key, fun) do
    case :global.trans({{:markdow_og_render, key}, self()}, fun, [node() | Node.list()], 60) do
      :aborted -> fun.()
      result -> result
    end
  end

  defp secret do
    :markdow
    |> Application.fetch_env!(MarkdowWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
  end

  defp escape(value), do: value |> Plug.HTML.html_escape() |> IO.iodata_to_binary()
end

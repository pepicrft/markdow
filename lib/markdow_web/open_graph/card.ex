defmodule MarkdowWeb.OpenGraph.Card do
  @moduledoc """
  Builds the self-contained HTML document rendered into an Open Graph image.

  The card draws from the same design tokens as the marketing pages
  (`MarkdowWeb.Theme`), so a change to the palette or the type scale reaches the
  social preview without a second definition. The document references no
  external asset because the headless browser renders it from a local file.

  Copy for the legal cards comes from `MarkdowWeb.LegalPage`, which keeps one
  title and one summary per document rather than a page copy and a card copy
  that drift apart.
  """

  alias MarkdowWeb.LegalPage
  alias MarkdowWeb.Theme

  @width 1200
  @height 630

  @legal_pages [:terms, :privacy, :cookies]

  @home %{
    eyebrow: "Programmatic access to Markdown notes",
    title: "A semantic layer for your Markdown.",
    subtitle:
      "One index over a folder of notes, served to editors, applications, and agents. The files remain ordinary Markdown."
  }

  @typedoc "A marketing page that has a social card."
  @type page :: :home | :terms | :privacy | :cookies

  @doc "The pixel dimensions every card is rendered at."
  @spec dimensions() :: {pos_integer(), pos_integer()}
  def dimensions, do: {@width, @height}

  @doc "Every page that has a card, in the order they appear on the site."
  @spec pages() :: [page()]
  def pages, do: [:home | @legal_pages]

  @doc "Parses an external page name, rejecting anything without a card."
  @spec parse(String.t()) :: {:ok, page()} | :error
  def parse(name) when is_binary(name) do
    Enum.find_value(pages(), :error, fn page ->
      if Atom.to_string(page) == name, do: {:ok, page}
    end)
  end

  @doc "Renders the card document for a page."
  @spec html(page()) :: String.t()
  def html(page) do
    %{eyebrow: eyebrow, title: title, subtitle: subtitle} = assigns(page)

    Theme.inject("""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <style>
          /* markdow-theme */

          * { box-sizing: border-box; margin: 0; padding: 0; }
          html, body { width: #{@width}px; height: #{@height}px; }
          body { background: var(--paper); color: var(--ink); font-family: var(--serif); overflow: hidden; }

          #og-card {
            --card-wordmark: 34px;
            --card-eyebrow: 20px;
            --card-title: 76px;
            --card-subtitle: 30px;

            display: grid;
            grid-template-rows: auto 1fr auto;
            gap: var(--space-9);
            padding: var(--space-11);
            height: 100%;

            & > [data-part="masthead"] {
              display: flex;
              align-items: baseline;
              justify-content: space-between;
              gap: var(--space-7);
              padding-bottom: var(--space-6);
              border-bottom: var(--rule-width) solid var(--ink);
              font-family: var(--sans);

              & > [data-part="wordmark"] {
                font-size: var(--card-wordmark);
                font-weight: var(--weight-display);
                letter-spacing: var(--tracking-heading);
              }

              & > [data-part="eyebrow"] {
                color: var(--accent);
                font-family: var(--mono);
                font-size: var(--card-eyebrow);
              }
            }

            & > [data-part="statement"] {
              align-self: center;
              border-left: var(--accent-width) solid var(--accent);
              padding-left: var(--space-7);

              & > [data-part="title"] {
                margin-bottom: var(--space-6);
                font-family: var(--sans);
                font-size: var(--card-title);
                font-weight: var(--weight-display);
                letter-spacing: var(--tracking-title);
                line-height: var(--leading-flat);
              }

              & > [data-part="subtitle"] {
                max-width: var(--measure-display);
                color: var(--muted);
                font-size: var(--card-subtitle);
                line-height: var(--leading-snug);
              }
            }

            & > [data-part="colophon"] {
              display: flex;
              justify-content: space-between;
              gap: var(--space-7);
              padding-top: var(--space-6);
              border-top: var(--rule-width) solid var(--rule);
              color: var(--muted);
              font-family: var(--sans);
              font-size: var(--card-eyebrow);
            }
          }
        </style>
      </head>
      <body>
        <div id="og-card">
          <header data-part="masthead">
            <span data-part="wordmark">markdow</span>
            <span data-part="eyebrow">#{escape(eyebrow)}</span>
          </header>
          <div data-part="statement">
            <p data-part="title">#{escape(title)}</p>
            <p data-part="subtitle">#{escape(subtitle)}</p>
          </div>
          <footer data-part="colophon">
            <span>markdow.org</span>
            <span>Markdown notes with a shared index.</span>
          </footer>
        </div>
      </body>
    </html>
    """)
  end

  defp assigns(:home), do: @home

  defp assigns(page) when page in @legal_pages do
    %{title: title, introduction: introduction} = LegalPage.metadata(page)

    %{eyebrow: "Legal", title: title, subtitle: introduction}
  end

  defp escape(value), do: value |> Plug.HTML.html_escape() |> IO.iodata_to_binary()
end

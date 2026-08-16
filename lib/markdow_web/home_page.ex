defmodule MarkdowWeb.HomePage do
  @moduledoc false

  @page ~S"""
  <!doctype html>
  <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="description" content="Markdow adds full-text search, backlinks, graph traversal, and programmatic access to a folder of Markdown notes.">
      <meta name="theme-color" content="#f8f7f2">
      <meta property="og:title" content="Markdow — Programmatic access to Markdown notes">
      <meta property="og:description" content="Keep the files you have. Use them from more places.">
      <meta property="og:type" content="website">
      <meta property="og:url" content="https://markdow.org/">
      <!-- markdow-og-image -->
      <!-- markdow-analytics -->
      <script defer src="/assets/home.js"></script>
      <title>Markdow — Programmatic access to Markdown notes</title>
      <style>
        /* markdow-theme */

        * { box-sizing: border-box; }
        html { scroll-behavior: smooth; }
        body {
          margin: 0;
          background: var(--paper);
          color: var(--ink);
          font-family: var(--serif);
          font-size: var(--text-root);
          line-height: var(--leading-normal);
          text-rendering: optimizeLegibility;
        }
        a { color: var(--accent); text-decoration-thickness: var(--rule-width); text-underline-offset: 3px; }
        a:hover { color: var(--ink); }
        code, pre { font-family: var(--mono); }

        #home {
          margin: 0 auto;
          width: min(var(--page-width), calc(100% - var(--page-gutter)));

          & > [data-part="masthead"] {
            display: flex;
            align-items: baseline;
            justify-content: space-between;
            gap: var(--space-7);
            padding: var(--space-6) 0;
            border-bottom: var(--rule-width) solid var(--ink);
            font-family: var(--sans);

            & > [data-part="identity"] {
              display: flex;
              align-items: baseline;
              gap: var(--space-4);
              color: inherit;
              text-decoration: none;

              & > strong { font-size: var(--text-feature); letter-spacing: var(--tracking-heading); }

              & > span {
                color: var(--muted);
                font-size: var(--text-mini);

                @media (max-width: 560px) {
                  & { display: none; }
                }
              }
            }

            & > [data-part="navigation"] {
              display: flex;
              gap: var(--space-6);
              font-size: var(--text-mini);

              & > a {
                color: var(--ink);
                text-decoration: none;

                &:hover { text-decoration: underline; }

                @media (max-width: 560px) {
                  &:not(:last-child) { display: none; }
                }
              }
            }
          }

          & [data-part="introduction"] {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(var(--column-aside), 1fr);
            gap: var(--space-12);
            padding: var(--space-13) 0;
            border-bottom: var(--rule-width) solid var(--rule);

            @media (max-width: 800px) {
              & { grid-template-columns: 1fr; gap: var(--space-9); padding: var(--space-11) 0; }
            }

            @media (max-width: 560px) {
              & { padding: var(--space-10) 0; }
            }

            & h1 {
              max-width: var(--measure-display);
              margin: 0 0 var(--space-7);
              font-family: var(--sans);
              font-size: var(--text-title);
              font-weight: var(--weight-display);
              letter-spacing: var(--tracking-title);
              line-height: var(--leading-flat);
            }

            & [data-part="standfirst"] {
              max-width: var(--measure-lead);
              margin: 0;
              font-size: var(--text-feature);
              line-height: var(--leading-snug);

              @media (max-width: 560px) {
                & { font-size: var(--text-lead); }
              }
            }

            & [data-part="note"] {
              align-self: end;
              margin-bottom: var(--space-1);
              padding-left: var(--space-5);
              border-left: var(--accent-width) solid var(--accent);
              color: var(--muted);
              font-size: var(--text-meta);

              @media (max-width: 800px) {
                & { max-width: var(--measure-aside); }
              }

              & > strong { display: block; margin-bottom: var(--space-2); color: var(--ink); font-family: var(--sans); font-size: var(--text-mini); }
              & > p { margin: 0 0 var(--space-3); }
              & > p:last-child { margin-bottom: 0; }
            }
          }

          & [data-part="sections"] {
            padding: var(--space-13) 0 var(--space-14);

            @media (max-width: 560px) {
              & { padding: var(--space-11) 0 var(--space-12); }
            }
          }

          & [data-part="section"] {
            display: grid;
            grid-template-columns: var(--column-label) minmax(0, 1fr);
            gap: var(--space-10);
            margin-bottom: var(--space-14);

            &:last-child { margin-bottom: 0; }

            @media (max-width: 800px) {
              & { grid-template-columns: 1fr; gap: var(--space-5); margin-bottom: var(--space-12); }
            }
          }

          & [data-part="label"] {
            padding-top: var(--space-2);
            color: var(--muted);
            font: var(--text-micro)/var(--leading-snug) var(--sans);

            @media (max-width: 800px) {
              & { max-width: var(--measure-label); }
            }

            & > span { display: block; margin-bottom: var(--space-2); color: var(--accent); font-family: var(--mono); }
          }

          & [data-part="prose"] {
            & h2 {
              margin: 0 0 var(--space-7);
              font-family: var(--sans);
              font-size: var(--text-heading);
              font-weight: var(--weight-semibold);
              letter-spacing: var(--tracking-heading);
              line-height: var(--leading-tight);
            }

            & p { max-width: var(--measure-prose); margin: 0 0 1.25em; }
            & p:last-child { margin-bottom: 0; }
            & [data-part="lead"] { font-size: var(--text-lead); line-height: var(--leading-snug); }
          }

          & [data-part="note-example"] {
            margin: var(--space-9) 0 0;

            & > figcaption {
              display: flex;
              justify-content: space-between;
              gap: var(--space-5);
              margin-bottom: var(--space-3);
              color: var(--muted);
              font: var(--text-micro)/var(--leading-snug) var(--sans);
            }

            & > pre {
              overflow-x: auto;
              margin: 0;
              padding: var(--space-6) var(--space-7);
              border: var(--rule-width) solid var(--rule);
              background: var(--wash);
              font-size: var(--text-small);
              line-height: var(--leading-loose);
            }

            & mark { background: var(--highlight); color: inherit; }
          }

          & [data-part="state-table"] {
            width: 100%;
            margin-top: var(--space-9);
            border-collapse: collapse;
            font-size: var(--text-meta);

            & th, & td { padding: var(--space-4) var(--space-4) var(--space-4) 0; border-bottom: var(--rule-width) solid var(--rule); text-align: left; vertical-align: top; }
            & thead th { border-top: var(--rule-width) solid var(--ink); border-bottom-color: var(--ink); font: var(--weight-semibold) var(--text-micro)/var(--leading-snug) var(--sans); }
            & tbody th { width: 25%; font-family: var(--mono); font-size: var(--text-mini); font-weight: var(--weight-medium); }
            & td { color: var(--muted); }

            @media (max-width: 560px) {
              & thead { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
              & tr { display: block; padding: var(--space-4) 0; border-bottom: var(--rule-width) solid var(--rule); }
              & tbody th, & td { display: block; width: 100%; padding: var(--space-1) 0; border: 0; }
            }
          }

          & [data-part="operation-list"] {
            margin: var(--space-8) 0 0;
            border-top: var(--rule-width) solid var(--ink);

            & > div {
              display: grid;
              grid-template-columns: var(--column-term) 1fr;
              gap: var(--space-7);
              padding: var(--space-5) 0;
              border-bottom: var(--rule-width) solid var(--rule);

              @media (max-width: 560px) {
                & { grid-template-columns: 1fr; gap: var(--space-1); }
              }
            }

            & dt { color: var(--accent); font: var(--text-mini)/var(--leading-normal) var(--mono); }
            & dd { margin: 0; font-size: var(--text-body); }
          }

          & [data-part="callout"] {
            margin: var(--space-9) 0 0;
            padding: var(--space-6) var(--space-7);
            border-left: var(--accent-width) solid var(--accent);
            background: var(--wash);
            font-size: var(--text-body);

            & strong { font-family: var(--sans); font-size: var(--text-label); }
          }

          & [data-part="commands"] { margin-top: var(--space-7); }

          & [data-part="closing"] {
            display: grid;
            grid-template-columns: 1fr auto;
            gap: var(--space-9);
            align-items: end;
            padding: var(--space-10) 0;
            border-top: var(--rule-width) solid var(--ink);

            @media (max-width: 560px) {
              & { grid-template-columns: 1fr; gap: var(--space-7); }
            }

            & > p { max-width: var(--measure-lead); margin: 0; font-size: var(--text-lead); line-height: var(--leading-snug); }
            & > a { font-family: var(--sans); font-size: var(--text-label); white-space: nowrap; }
          }

          & > [data-part="colophon"] {
            display: flex;
            justify-content: space-between;
            gap: var(--space-7);
            padding: var(--space-6) 0 var(--space-7);
            border-top: var(--rule-width) solid var(--rule);
            color: var(--muted);
            font: var(--text-micro)/var(--leading-normal) var(--sans);

            @media (max-width: 560px) {
              & { display: block; }
            }

            & > nav {
              display: flex;
              flex-wrap: wrap;
              justify-content: flex-end;
              gap: var(--space-5);

              @media (max-width: 560px) {
                & { justify-content: flex-start; margin-top: var(--space-3); }
              }
            }
          }
        }

        [data-part="copy-prompt"] {
          --copy-button-width: 76px;

          position: relative;

          & > pre {
            overflow-x: auto;
            margin: 0 0 var(--space-3);
            padding: var(--space-6) calc(var(--copy-button-width) + var(--space-7)) var(--space-6) var(--space-7);
            background: var(--ink);
            color: var(--ink-inverted);
            font-size: var(--text-mini);
            line-height: var(--leading-loose);
          }

          & > [data-part="copy-button"] {
            position: absolute;
            top: var(--space-3);
            right: var(--space-3);
            min-width: var(--copy-button-width);
            border: var(--rule-width) solid var(--rule-inverted);
            border-radius: 0;
            padding: var(--space-2) var(--space-3);
            background: transparent;
            color: var(--ink-inverted);
            cursor: pointer;
            font: var(--text-micro)/var(--leading-flat) var(--mono);

            &:hover { border-color: var(--ink-inverted); background: var(--ink-inverted); color: var(--ink); }
            &:focus-visible { outline: var(--accent-width) solid var(--ink-inverted); outline-offset: var(--space-1); }
            &[data-state="copied"] { border-color: var(--positive-rule); color: var(--positive-ink); }
            &[data-state="error"] { border-color: var(--negative-rule); color: var(--negative-ink); }
          }

          & > [data-part="status"] {
            position: absolute;
            width: 1px;
            height: 1px;
            padding: 0;
            margin: -1px;
            overflow: hidden;
            clip: rect(0, 0, 0, 0);
            white-space: nowrap;
            border: 0;
          }
        }

        @media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
      </style>
    </head>
    <body data-analytics-page-event="marketing_viewed">
      <div id="home">
        <header data-part="masthead">
          <a data-part="identity" href="/"><strong>markdow</strong><span>Programmatic access to Markdown notes</span></a>
          <nav data-part="navigation" aria-label="Primary navigation"><a href="#about">About</a><a href="#works">How it works</a><a href="#agent-access">Agent access</a><a href="#contributing">Contributing</a><a href="/docs" data-analytics-event="documentation_opened">Documentation</a></nav>
        </header>

        <main data-part="body">
          <section data-part="introduction" aria-labelledby="introduction-title">
            <div data-part="statement">
              <h1 id="introduction-title">A semantic layer for your Markdown.</h1>
              <p data-part="standfirst">Markdow indexes a vault once, then makes the same notes, metadata, backlinks, and graph available to editors, applications, and agents. The files remain ordinary Markdown.</p>
            </div>
            <aside data-part="note">
              <strong>How it fits</strong>
              <p>Obsidian edits the files. Markdow serves the same vault to applications and agents.</p>
              <p>There is no second copy of your notes to keep in sync.</p>
            </aside>
          </section>

          <article data-part="sections">
            <section data-part="section" id="about" aria-labelledby="about-title">
              <p data-part="label"><span>About</span>The useful boundary</p>
              <div data-part="prose">
                <h2 id="about-title">The file is the durable part.</h2>
                <p data-part="lead">A folder is a good place to keep notes. It is easy to inspect, back up, move, and version. It is less good at answering questions that involve the whole collection.</p>
                <p>Markdow adds the missing context without replacing the folder. It extracts frontmatter, resolves wiki links, records backlinks, and builds full-text search. The derived data can be discarded and rebuilt from the files.</p>
                <p>The separation becomes useful when the same notes need to appear in more than one place. An editor can work directly with the vault while an application or agent uses Markdow. Both are looking at the same underlying material.</p>

                <figure data-part="note-example">
                  <figcaption><span>A note as Markdow sees it</span><span>projects/markdow/architecture.md</span></figcaption>
                  <pre>---
  title: Architecture
  tags: [markdow, engineering]
  ---

  # Architecture

  Markdown files are the content source of truth.
  PostgreSQL carries the index. See <mark>[[Project plan]]</mark>.</pre>
                </figure>
              </div>
            </section>

            <section data-part="section" id="works" aria-labelledby="works-title">
              <p data-part="label"><span>How it works</span>Three kinds of state</p>
              <div data-part="prose">
                <h2 id="works-title">There is very little machinery.</h2>
                <p>The storage driver reads and writes note bodies. PostgreSQL holds the note index, extracted relationships, and access records. The <a href="/openapi.json" title="Representational State Transfer application programming interface">REST API</a> and <a href="/.well-known/mcp/server-card.json" title="Model Context Protocol">MCP server</a> expose the same note operations to clients.</p>

                <table data-part="state-table">
                  <thead><tr><th>Layer</th><th>What it holds</th><th>What happens without it</th></tr></thead>
                  <tbody>
                    <tr><th>Markdown vault</th><td>Note bodies and assets</td><td>The notes remain ordinary files.</td></tr>
                    <tr><th>PostgreSQL</th><td>Search, tags, links, graph, and access records</td><td>The note index can be rebuilt; access must be established again.</td></tr>
                    <tr><th>Client</th><td>The editing or reading interface</td><td>Choose another client without converting the notes.</td></tr>
                  </tbody>
                </table>
              </div>
            </section>

            <section data-part="section" aria-labelledby="operations-title">
              <p data-part="label"><span>Operations</span>One shared contract</p>
              <div data-part="prose">
                <h2 id="operations-title">Work with notes from any client.</h2>
                <p>It creates users and their vaults, then creates, reads, updates, deletes, imports, and lists the notes inside each vault. The same vault-scoped index supports these higher-level operations:</p>
                <dl data-part="operation-list">
                  <div><dt>search_notes</dt><dd>Search titles and bodies and return a relevant excerpt.</dd></div>
                  <div><dt>list_backlinks</dt><dd>Find notes that link to a given note, including the surrounding sentence.</dd></div>
                  <div><dt>get_note_graph</dt><dd>Traverse linked notes to a requested depth.</dd></div>
                  <div><dt>rebuild_index</dt><dd>Read the vault again and reconstruct its derived state.</dd></div>
                  <div><dt>embed_text</dt><dd>Create an embedding with a vault owner's encrypted provider credential.</dd></div>
                </dl>
                <aside data-part="callout"><strong>One operation, one contract.</strong> When a note operation changes, its web route, <a href="/openapi.json">OpenAPI description</a>, and <a href="https://modelcontextprotocol.io/" title="Model Context Protocol">MCP</a> tool are updated and tested together.</aside>
              </div>
            </section>

            <section data-part="section" id="agent-access" aria-labelledby="agent-access-title">
              <p data-part="label"><span>Get started</span>One prompt</p>
              <div data-part="prose">
                <h2 id="agent-access-title">Copy this into your agent.</h2>
                <div data-part="commands">
                  <div data-part="copy-prompt">
                    <pre id="agent-signup-prompt">Sign me up for Markdow using https://markdow.org/auth.md.
  Ask me for anything you need, then create my first vault.</pre>
                    <button data-part="copy-button" type="button" data-copy-target="agent-signup-prompt" data-analytics-event="agent_prompt_copied" aria-label="Copy the agent sign-up prompt">Copy</button>
                    <span data-part="status" data-copy-status role="status" aria-live="polite"></span>
                  </div>
                </div>
              </div>
            </section>
            <section data-part="section" id="contributing" aria-labelledby="contributing-title">
              <p data-part="label"><span>Contributing</span>Code and design</p>
              <div data-part="prose">
                <h2 id="contributing-title">Markdow is small enough to change.</h2>
                <p data-part="lead">An Elixir service, a PostgreSQL index, and a folder of Markdown files. There is little machinery between an idea and a working patch.</p>
                <p>Code is welcome. A storage driver, a note operation, better indexing, or a client for the editor you already use. When an operation changes, its web route, its <a href="/openapi.json">OpenAPI description</a>, and its <a href="https://modelcontextprotocol.io/" title="Model Context Protocol">Model Context Protocol</a> tool are updated and tested together, so a contribution stays consistent across every interface.</p>
                <p>Design is welcome on the same terms. These pages, the documentation, and the social preview images read from one set of design tokens, so a considered change to the palette, the type scale, or a layout reaches all of them at once. A proposal is as useful as a patch.</p>
                <aside data-part="callout"><strong>Where to start.</strong> Read the <a href="https://github.com/pepicrft/markdow" data-analytics-event="source_opened">source</a>, open or claim an <a href="https://github.com/pepicrft/markdow/issues" data-analytics-event="issues_opened">issue</a>, and describe what you plan to change before writing much of it.</aside>
              </div>
            </section>
          </article>

          <section data-part="closing" aria-label="Project source">
            <p>Prefer to host Markdow yourself? Go for it.</p>
            <a href="https://github.com/pepicrft/markdow" data-analytics-event="source_opened">Get the source on GitHub →</a>
          </section>
        </main>

        <footer data-part="colophon">
          <div>markdow.org · Markdown notes with a shared index.</div>
          <nav aria-label="Service links"><a href="/health">Service health</a><a href="/docs">Documentation</a><a href="/auth.md">Agent access</a><a href="/terms">Terms</a><a href="/privacy">Privacy</a><a href="/cookies">Cookies</a><a href="https://github.com/pepicrft/markdow/issues">Project help</a></nav>
        </footer>
      </div>
    </body>
  </html>
  """

  @document MarkdowWeb.Theme.inject(@page)

  @doc """
  Renders the page.

  Options:

    * `:analytics` - the endpoint's analytics configuration
    * `:base_url` - the externally visible origin, needed to advertise the
      social card; omitting it renders the page without one
    * `:open_graph` - the social card configuration
  """
  @spec html(keyword()) :: String.t()
  def html(opts \\ []) do
    @document
    |> String.replace("<!-- markdow-analytics -->", analytics_markup(opts[:analytics] || []))
    |> String.replace("<!-- markdow-og-image -->", social_markup(opts))
  end

  defp social_markup(opts) do
    case Keyword.get(opts, :base_url) do
      base_url when is_binary(base_url) and base_url != "" ->
        MarkdowWeb.OpenGraph.meta_tags(:home, base_url, Keyword.get(opts, :open_graph, []))

      _missing ->
        ""
    end
  end

  defp analytics_markup(analytics) do
    with true <- Keyword.get(analytics, :enabled, false),
         host when is_binary(host) and host != "" <- Keyword.get(analytics, :host),
         write_key when is_binary(write_key) and write_key != "" <-
           Keyword.get(analytics, :write_key) do
      """
      <meta name="smolanalytics-host" content="#{Plug.HTML.html_escape(host)}">
      <meta name="smolanalytics-write-key" content="#{Plug.HTML.html_escape(write_key)}">
      <script defer src="/assets/analytics.js"></script>
      """
    else
      _disabled -> ""
    end
  end
end

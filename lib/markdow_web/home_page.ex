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
      <!-- markdow-analytics -->
      <script defer src="/assets/home.js"></script>
      <title>Markdow — Programmatic access to Markdown notes</title>
      <style>
        :root {
          color-scheme: light;
          --paper: #f8f7f2;
          --ink: #24231f;
          --muted: #6e6b62;
          --rule: #cfccc2;
          --wash: #efede5;
          --accent: #285d4b;
          --serif: Charter, "Bitstream Charter", "Iowan Old Style", Georgia, serif;
          --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
          --mono: "SFMono-Regular", Consolas, "Liberation Mono", monospace;
        }

        * { box-sizing: border-box; }
        html { scroll-behavior: smooth; }
        body {
          margin: 0;
          background: var(--paper);
          color: var(--ink);
          font-family: var(--serif);
          font-size: 18px;
          line-height: 1.55;
          text-rendering: optimizeLegibility;
        }
        a { color: var(--accent); text-decoration-thickness: 1px; text-underline-offset: 3px; }
        a:hover { color: var(--ink); }
        code, pre { font-family: var(--mono); }
        .page { width: min(1120px, calc(100% - 48px)); margin: 0 auto; }

        header {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 32px;
          padding: 27px 0 24px;
          border-bottom: 1px solid var(--ink);
          font-family: var(--sans);
        }
        .identity { display: flex; align-items: baseline; gap: 15px; color: inherit; text-decoration: none; }
        .identity strong { font-size: 24px; letter-spacing: -.045em; }
        .identity span { color: var(--muted); font-size: 12px; }
        header nav { display: flex; gap: 22px; font-size: 12px; }
        header nav a { color: var(--ink); text-decoration: none; }
        header nav a:hover { text-decoration: underline; }

        .introduction {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(240px, 1fr);
          gap: 90px;
          padding: 112px 0 118px;
          border-bottom: 1px solid var(--rule);
        }
        h1 {
          max-width: 780px;
          margin: 0 0 34px;
          font-family: var(--sans);
          font-size: clamp(50px, 6.2vw, 78px);
          font-weight: 650;
          letter-spacing: -.06em;
          line-height: 1;
        }
        .standfirst { max-width: 730px; margin: 0; font-size: 24px; line-height: 1.42; }
        .introduction__note {
          align-self: end;
          margin-bottom: 6px;
          padding-left: 20px;
          border-left: 2px solid var(--accent);
          color: var(--muted);
          font-size: 15px;
        }
        .introduction__note strong { display: block; margin-bottom: 8px; color: var(--ink); font-family: var(--sans); font-size: 12px; }
        .introduction__note p { margin: 0 0 12px; }
        .introduction__note p:last-child { margin-bottom: 0; }

        article { padding: 105px 0 125px; }
        .section {
          display: grid;
          grid-template-columns: 180px minmax(0, 760px);
          gap: 60px;
          justify-content: center;
          margin-bottom: 125px;
        }
        .section:last-child { margin-bottom: 0; }
        .margin-label {
          padding-top: 9px;
          color: var(--muted);
          font: 11px/1.4 var(--sans);
        }
        .margin-label span { display: block; margin-bottom: 7px; color: var(--accent); font-family: var(--mono); }
        h2 {
          margin: 0 0 32px;
          font-family: var(--sans);
          font-size: clamp(34px, 4vw, 50px);
          font-weight: 600;
          letter-spacing: -.045em;
          line-height: 1.08;
        }
        .prose p { margin: 0 0 1.25em; }
        .prose p:last-child { margin-bottom: 0; }
        .prose .lead { font-size: 22px; line-height: 1.45; }

        .note-example { margin: 46px 0 0; }
        .note-example figcaption {
          display: flex;
          justify-content: space-between;
          gap: 20px;
          margin-bottom: 10px;
          color: var(--muted);
          font: 11px/1.4 var(--sans);
        }
        .note-example pre {
          overflow-x: auto;
          margin: 0;
          padding: 25px 28px;
          border: 1px solid var(--rule);
          background: var(--wash);
          font-size: 13px;
          line-height: 1.7;
        }
        .note-example mark { background: #dce8d8; color: inherit; }

        .state-table { width: 100%; margin-top: 44px; border-collapse: collapse; font-size: 15px; }
        .state-table th, .state-table td { padding: 17px 15px 17px 0; border-bottom: 1px solid var(--rule); text-align: left; vertical-align: top; }
        .state-table thead th { border-top: 1px solid var(--ink); border-bottom-color: var(--ink); font: 600 11px/1.3 var(--sans); }
        .state-table tbody th { width: 25%; font-family: var(--mono); font-size: 12px; font-weight: 500; }
        .state-table td { color: var(--muted); }

        .operation-list { margin: 42px 0 0; border-top: 1px solid var(--ink); }
        .operation-list > div {
          display: grid;
          grid-template-columns: 190px 1fr;
          gap: 28px;
          padding: 18px 0;
          border-bottom: 1px solid var(--rule);
        }
        .operation-list dt { color: var(--accent); font: 12px/1.5 var(--mono); }
        .operation-list dd { margin: 0; font-size: 16px; }

        .aside {
          margin: 44px 0 0;
          padding: 26px 28px;
          border-left: 2px solid var(--accent);
          background: var(--wash);
          font-size: 16px;
        }
        .aside strong { font-family: var(--sans); font-size: 14px; }

        .commands { margin-top: 36px; }
        .copy-prompt { position: relative; }
        .commands pre {
          overflow-x: auto;
          margin: 0 0 12px;
          padding: 25px 110px 25px 28px;
          background: var(--ink);
          color: #f5f3eb;
          font-size: 12px;
          line-height: 1.65;
        }
        .copy-prompt__button {
          position: absolute;
          top: 14px;
          right: 14px;
          min-width: 76px;
          border: 1px solid #77746d;
          border-radius: 0;
          padding: 8px 12px;
          background: transparent;
          color: #f5f3eb;
          cursor: pointer;
          font: 11px/1 var(--mono);
        }
        .copy-prompt__button:hover { border-color: #f5f3eb; background: #f5f3eb; color: var(--ink); }
        .copy-prompt__button:focus-visible { outline: 2px solid #f5f3eb; outline-offset: 3px; }
        .copy-prompt__button[data-state="copied"] { border-color: #9cc5ae; color: #b8dec7; }
        .copy-prompt__button[data-state="error"] { border-color: #e5a69a; color: #f1b7ac; }
        .visually-hidden {
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
        .commands p { margin: 18px 0 0; font-size: 15px; }

        .closing {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: 48px;
          align-items: end;
          padding: 65px 0 70px;
          border-top: 1px solid var(--ink);
        }
        .closing p { max-width: 680px; margin: 0; font-size: 22px; line-height: 1.4; }
        .closing a { font-family: var(--sans); font-size: 14px; white-space: nowrap; }

        footer {
          display: flex;
          justify-content: space-between;
          gap: 36px;
          padding: 24px 0 35px;
          border-top: 1px solid var(--rule);
          color: var(--muted);
          font: 11px/1.5 var(--sans);
        }
        footer nav { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 18px; }

        @media (max-width: 800px) {
          .page { width: min(100% - 32px, 680px); }
          .introduction { grid-template-columns: 1fr; gap: 48px; padding: 80px 0; }
          .introduction__note { max-width: 540px; }
          .section { grid-template-columns: 1fr; gap: 18px; margin-bottom: 90px; }
          .margin-label { max-width: 300px; }
        }

        @media (max-width: 560px) {
          body { font-size: 17px; }
          .page { width: min(100% - 24px, 520px); }
          .identity span, header nav a:not(:last-child) { display: none; }
          .introduction { padding: 65px 0 70px; }
          h1 { font-size: clamp(44px, 13vw, 62px); }
          .standfirst { font-size: 21px; }
          article { padding: 75px 0 90px; }
          .operation-list > div { grid-template-columns: 1fr; gap: 5px; }
          .state-table thead { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
          .state-table tr { display: block; padding: 15px 0; border-bottom: 1px solid var(--rule); }
          .state-table tbody th, .state-table td { display: block; width: 100%; padding: 2px 0; border: 0; }
          .closing { grid-template-columns: 1fr; gap: 28px; }
          footer { display: block; }
          footer nav { justify-content: flex-start; margin-top: 14px; }
        }

        @media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
      </style>
    </head>
    <body data-analytics-page-event="marketing_viewed">
      <div class="page">
        <header>
          <a class="identity" href="/"><strong>markdow</strong><span>Programmatic access to Markdown notes</span></a>
          <nav aria-label="Primary navigation"><a href="#about">About</a><a href="#works">How it works</a><a href="#agent-access">Agent access</a><a href="/docs" data-analytics-event="documentation_opened">Documentation</a></nav>
        </header>

        <main>
          <section class="introduction" aria-labelledby="introduction-title">
            <div>
              <h1 id="introduction-title">A semantic layer for your Markdown.</h1>
              <p class="standfirst">Markdow indexes a vault once, then makes the same notes, metadata, backlinks, and graph available to editors, applications, and agents. The files remain ordinary Markdown.</p>
            </div>
            <aside class="introduction__note">
              <strong>How it fits</strong>
              <p>Obsidian edits the files. Markdow serves the same vault to applications and agents.</p>
              <p>There is no second copy of your notes to keep in sync.</p>
            </aside>
          </section>

          <article>
            <section class="section" id="about" aria-labelledby="about-title">
              <p class="margin-label"><span>About</span>The useful boundary</p>
              <div class="prose">
                <h2 id="about-title">The file is the durable part.</h2>
                <p class="lead">A folder is a good place to keep notes. It is easy to inspect, back up, move, and version. It is less good at answering questions that involve the whole collection.</p>
                <p>Markdow adds the missing context without replacing the folder. It extracts frontmatter, resolves wiki links, records backlinks, and builds full-text search. The derived data can be discarded and rebuilt from the files.</p>
                <p>The separation becomes useful when the same notes need to appear in more than one place. An editor can work directly with the vault while an application or agent uses Markdow. Both are looking at the same underlying material.</p>

                <figure class="note-example">
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

            <section class="section" id="works" aria-labelledby="works-title">
              <p class="margin-label"><span>How it works</span>Three kinds of state</p>
              <div class="prose">
                <h2 id="works-title">There is very little machinery.</h2>
                <p>The storage driver reads and writes note bodies. PostgreSQL holds the note index, extracted relationships, and access records. The <a href="/openapi.json" title="Representational State Transfer application programming interface">REST API</a> and <a href="/.well-known/mcp/server-card.json" title="Model Context Protocol">MCP server</a> expose the same note operations to clients.</p>

                <table class="state-table">
                  <thead><tr><th>Layer</th><th>What it holds</th><th>What happens without it</th></tr></thead>
                  <tbody>
                    <tr><th>Markdown vault</th><td>Note bodies and assets</td><td>The notes remain ordinary files.</td></tr>
                    <tr><th>PostgreSQL</th><td>Search, tags, links, graph, and access records</td><td>The note index can be rebuilt; access must be established again.</td></tr>
                    <tr><th>Client</th><td>The editing or reading interface</td><td>Choose another client without converting the notes.</td></tr>
                  </tbody>
                </table>
              </div>
            </section>

            <section class="section" aria-labelledby="operations-title">
              <p class="margin-label"><span>Operations</span>One shared contract</p>
              <div class="prose">
                <h2 id="operations-title">Work with notes from any client.</h2>
                <p>It creates users and their vaults, then creates, reads, updates, deletes, imports, and lists the notes inside each vault. The same vault-scoped index supports these higher-level operations:</p>
                <dl class="operation-list">
                  <div><dt>search_notes</dt><dd>Search titles and bodies and return a relevant excerpt.</dd></div>
                  <div><dt>list_backlinks</dt><dd>Find notes that link to a given note, including the surrounding sentence.</dd></div>
                  <div><dt>get_note_graph</dt><dd>Traverse linked notes to a requested depth.</dd></div>
                  <div><dt>rebuild_index</dt><dd>Read the vault again and reconstruct its derived state.</dd></div>
                  <div><dt>embed_text</dt><dd>Create an embedding with a vault owner's encrypted provider credential.</dd></div>
                </dl>
                <aside class="aside"><strong>One operation, one contract.</strong> When a note operation changes, its web route, <a href="/openapi.json">OpenAPI description</a>, and <a href="https://modelcontextprotocol.io/" title="Model Context Protocol">MCP</a> tool are updated and tested together.</aside>
              </div>
            </section>

            <section class="section" id="agent-access" aria-labelledby="agent-access-title">
              <p class="margin-label"><span>Get started</span>One prompt</p>
              <div class="prose">
                <h2 id="agent-access-title">Copy this into your agent.</h2>
                <div class="commands">
                  <div class="copy-prompt">
                    <pre id="agent-signup-prompt">Sign me up for Markdow using https://markdow.org/auth.md.
  Ask me for anything you need, then create my first vault.</pre>
                    <button class="copy-prompt__button" type="button" data-copy-target="agent-signup-prompt" data-analytics-event="agent_prompt_copied" aria-label="Copy the agent sign-up prompt">Copy</button>
                    <span class="visually-hidden" data-copy-status role="status" aria-live="polite"></span>
                  </div>
                </div>
              </div>
            </section>
          </article>

          <section class="closing" aria-label="Project source">
            <p>Prefer to host Markdow yourself? Go for it.</p>
            <a href="https://github.com/pepicrft/markdow" data-analytics-event="source_opened">Get the source on GitHub →</a>
          </section>
        </main>

        <footer>
          <div>markdow.org · Markdown notes with a shared index.</div>
          <nav aria-label="Service links"><a href="/health">Service health</a><a href="/docs">Documentation</a><a href="/auth.md">Agent access</a><a href="/terms">Terms</a><a href="/privacy">Privacy</a><a href="/cookies">Cookies</a><a href="https://github.com/pepicrft/markdow/issues">Project help</a></nav>
        </footer>
      </div>
    </body>
  </html>
  """

  @spec html(keyword()) :: String.t()
  def html(analytics \\ []) do
    String.replace(@page, "<!-- markdow-analytics -->", analytics_markup(analytics))
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

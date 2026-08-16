defmodule MarkdowWeb.LegalPage do
  @moduledoc false

  @documents %{
    terms: %{
      title: "Terms of service",
      introduction: "The simple terms for using the free Markdow service.",
      path: "/terms"
    },
    privacy: %{
      title: "Privacy policy",
      introduction: "What a hosted Markdow instance processes and why.",
      path: "/privacy"
    },
    cookies: %{
      title: "Cookie terms",
      introduction: "How Markdow uses browser storage and anonymous audience measurement.",
      path: "/cookies"
    }
  }

  @typedoc "A legal document Markdow publishes."
  @type document :: :terms | :privacy | :cookies

  @doc """
  The title, summary, and path of a legal document.

  The social card renders from the same values as the page, so a wording change
  reaches both.
  """
  @spec metadata(document()) :: %{title: String.t(), introduction: String.t(), path: String.t()}
  def metadata(document), do: Map.fetch!(@documents, document)

  @spec terms(keyword(), keyword()) :: String.t()
  def terms(legal, opts \\ []) do
    page(
      :terms,
      legal,
      opts,
      """
      <section>
        <h2>1. The service</h2>
        <p>Markdow is an early, free service for storing, indexing, searching, and connecting Markdown notes. These terms apply to a Markdow instance operated by the provider named below. A self-hosted installation is operated under the self-hoster's own terms.</p>
        <p>There is no charge for the hosted service at present. We will give reasonable advance notice before introducing a paid plan, and continued free use will not by itself enroll you in a paid plan.</p>
      </section>
      <section>
        <h2>2. Accounts, vaults, and content</h2>
        <p>You are responsible for activity performed with your credentials and for maintaining your own backups. Each note belongs to a vault, and each vault belongs to a user.</p>
        <p>You keep ownership of your content. You give the provider only the limited permission needed to store, copy, index, transmit, and display that content for operating the service.</p>
      </section>
      <section>
        <h2>3. Acceptable use</h2>
        <p>Do not use Markdow to break the law, infringe another person's rights, distribute malware, probe or disrupt systems without permission, evade rate limits, or interfere with other users. Do not place content in a vault unless you have the right to process it.</p>
      </section>
      <section>
        <h2>4. Availability and changes</h2>
        <p>The service is provided without a guaranteed availability level. Features may change, and the service may be suspended for maintenance, security, abuse prevention, or legal reasons. We may discontinue the free hosted service after reasonable notice where practicable.</p>
      </section>
      <section>
        <h2>5. Ending use</h2>
        <p>You may stop using the service at any time. We may restrict or end access for a material breach, a security risk, unlawful use, or sustained abuse. Where practicable, we will provide an opportunity to export content before a non-urgent closure.</p>
      </section>
      <section>
        <h2>6. Responsibility</h2>
        <p>Markdow is supplied as early software. Nothing in these terms excludes liability that cannot lawfully be excluded, including liability for intent, gross negligence, fraud, or injury to life, body, or health. Mandatory consumer rights remain unaffected.</p>
      </section>
      <section>
        <h2>7. Law and disputes</h2>
        <p>The law at the provider's place of establishment applies, except where mandatory consumer law provides stronger protection. No exclusive place of jurisdiction is imposed on consumers.</p>
        <p>The provider is not willing or obliged to participate in dispute resolution proceedings before a consumer arbitration body.</p>
      </section>
      <section>
        <h2>8. Provider information</h2>
        #{provider_details(legal)}
      </section>
      <section>
        <h2>9. Changes to these terms</h2>
        <p>We may update these terms for legal, security, or product changes. Material changes will be announced reasonably in advance where practicable. The effective date below identifies the current version.</p>
      </section>
      """
    )
  end

  @spec privacy(keyword(), keyword()) :: String.t()
  def privacy(legal, opts \\ []) do
    page(
      :privacy,
      legal,
      opts,
      """
      <section>
        <h2>1. Controller</h2>
        #{provider_details(legal)}
        <p>This notice covers the hosted instance operated by that provider. A person or organization running a self-hosted instance is responsible for its own deployment and privacy notice.</p>
      </section>
      <section>
        <h2>2. Data we process</h2>
        <ul>
          <li>Account data such as user identifiers, names, and email addresses.</li>
          <li>Vault data, Markdown note bodies, frontmatter, tags, links, assets, and derived search records.</li>
          <li>Authentication data such as claim email addresses, hashed credentials, access scopes, expiry times, and security events.</li>
          <li>Technical data such as Internet Protocol addresses, request times, requested routes, response status, and in-memory abuse-prevention counters.</li>
          <li>When audience measurement is enabled, anonymous page and named interaction events from the marketing page. No form values, account identifiers, note data, or credentials are attached to these events.</li>
        </ul>
      </section>
      <section>
        <h2>3. Purposes and legal bases</h2>
        <p>We process account and vault data to provide the service you request and to take steps connected with that service. We process security, request, and rate-limit data for our legitimate interests in protecting Markdow, preventing abuse, diagnosing failures, and keeping the service available. Where consent is legally required for a future feature, we will ask before enabling it.</p>
      </section>
      <section>
        <h2>4. Recipients and transfers</h2>
        <p>Infrastructure providers may process data only as needed to host the application, database, storage, network, mail relay, and anonymous audience measurement. The marketing page may load <a href="https://github.com/Arjun0606/smolanalytics">smolanalytics</a> from the operator's configured analytics host. The interactive documentation page downloads the Scalar library from <a href="https://www.jsdelivr.com/terms/privacy-policy">jsDelivr</a>; that request exposes the usual network and browser information to jsDelivr and its network providers.</p>
        <p>Provider locations depend on the deployed infrastructure. If data is transferred outside the European Economic Area, the operator must use a lawful transfer mechanism and document it here.</p>
      </section>
      <section>
        <h2>5. Retention</h2>
        <p>Account and vault data are kept while the service is provided and then removed or anonymized when no longer needed, subject to backups, security needs, and legal retention duties. Expired or revoked authentication records and security events are retained only as long as needed for security and accountability. Local Hammer rate-limit counters are held in memory temporarily and are cleaned automatically. Hosting logs may have a separate short retention period set by the deployment operator.</p>
      </section>
      <section>
        <h2>6. Your rights</h2>
        <p>Depending on the circumstances, you may request access, correction, deletion, restriction, portability, or object to processing. You may withdraw consent without affecting earlier processing. You may also complain to a data protection supervisory authority, particularly in the European Union country of your residence, workplace, or the alleged infringement.</p>
        <p>Send a request to <a href="mailto:#{email(legal)}">#{email(legal)}</a>. We may need to verify that the request concerns your account.</p>
      </section>
      <section>
        <h2>7. Automated decisions</h2>
        <p>Markdow does not make decisions with legal or similarly significant effects through automated processing.</p>
      </section>
      """
    )
  end

  @spec cookies(keyword(), keyword()) :: String.t()
  def cookies(legal, opts \\ []) do
    page(
      :cookies,
      legal,
      opts,
      """
      <section>
        <h2>No advertising or analytics cookies</h2>
        <p>The Markdow marketing pages do not set analytics cookies, run advertising technology, or measure people across websites. When anonymous audience measurement is configured, it uses a daily rotating identifier without writing an identifier to browser storage. No account, form, credential, or note values are sent with an event.</p>
      </section>
      <section>
        <h2>Interactive documentation</h2>
        <p>The <a href="/docs">interactive documentation</a> downloads the Scalar client-side library from jsDelivr. Scalar is configured with authentication persistence and telemetry disabled. Markdow does not ask Scalar to store your access credential between page loads. Your browser may still cache ordinary page resources according to standard web behavior.</p>
      </section>
      <section>
        <h2>Operational clients</h2>
        <p>The application programming interface and Model Context Protocol server use authorization headers rather than browser cookies. A third-party client may have its own storage behavior and privacy notice.</p>
      </section>
      <section>
        <h2>If this changes</h2>
        <p>If a future version introduces optional device storage or tracking, this notice and the consent flow will be updated before that technology is enabled. Questions can be sent to <a href="mailto:#{email(legal)}">#{email(legal)}</a>.</p>
      </section>
      """
    )
  end

  defp page(document, legal, opts, content) do
    %{title: title, introduction: introduction} = metadata(document)

    MarkdowWeb.Theme.inject("""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="description" content="#{escape(introduction)}">
        #{social_markup(document, opts)}
        <title>#{escape(title)} · Markdow</title>
        <style>
          /* markdow-theme */

          * { box-sizing: border-box; }
          body { margin: 0; background: var(--paper); color: var(--ink); font-family: var(--serif); font-size: var(--text-root); line-height: var(--leading-normal); }
          a { color: var(--accent); text-underline-offset: 3px; }

          #legal {
            --page-width: 780px;
            --page-gutter: 40px;

            margin: 0 auto;
            width: min(var(--page-width), calc(100% - var(--page-gutter)));

            & > [data-part="masthead"] {
              display: flex;
              justify-content: space-between;
              gap: var(--space-6);
              padding: var(--space-6) 0;
              border-bottom: var(--rule-width) solid var(--ink);
              font: var(--text-small)/var(--leading-snug) var(--sans);

              & a { color: var(--ink); text-decoration: none; }
              & > nav { display: flex; flex-wrap: wrap; gap: var(--space-4); }

              @media (max-width: 620px) {
                & { display: block; }
                & > nav { margin-top: var(--space-3); }
              }
            }

            & > [data-part="body"] {
              padding: var(--space-11) 0 var(--space-12);

              @media (max-width: 620px) {
                & { padding-top: var(--space-10); }
              }

              & h1 {
                margin: 0 0 var(--space-5);
                font-family: var(--sans);
                font-size: var(--text-title);
                letter-spacing: var(--tracking-heading);
                line-height: var(--leading-tight);
              }

              & h2 {
                margin: 0 0 var(--space-4);
                font-family: var(--sans);
                font-size: var(--text-subheading);
                letter-spacing: var(--tracking-heading);
                line-height: var(--leading-tight);
              }

              & > [data-part="introduction"] {
                margin: 0 0 var(--space-10);
                color: var(--muted);
                font-size: var(--text-lead);
              }

              & section {
                padding: var(--space-7) 0;
                border-top: var(--rule-width) solid var(--rule);

                & p, & ul { margin: 0 0 var(--space-4); }
                & p:last-child, & ul:last-child { margin-bottom: 0; }
              }

              & address { font-style: normal; }
            }

            & > [data-part="colophon"] {
              display: flex;
              justify-content: space-between;
              gap: var(--space-6);
              padding: var(--space-6) 0 var(--space-7);
              border-top: var(--rule-width) solid var(--rule);
              color: var(--muted);
              font: var(--text-mini)/var(--leading-normal) var(--sans);

              @media (max-width: 620px) {
                & { display: block; }
              }
            }
          }
        </style>
      </head>
      <body>
        <div id="legal">
          <header data-part="masthead"><a href="/"><strong>markdow</strong></a><nav><a href="/terms">Terms</a><a href="/privacy">Privacy</a><a href="/cookies">Cookies</a></nav></header>
          <main data-part="body">
            <h1>#{escape(title)}</h1>
            <p data-part="introduction">#{escape(introduction)}</p>
            #{content}
          </main>
          <footer data-part="colophon"><span>Effective #{escape(Keyword.fetch!(legal, :effective_date))}</span><a href="/">Return to Markdow</a></footer>
        </div>
      </body>
    </html>
    """)
  end

  # Social metadata needs the externally visible origin, which only the request
  # knows, so a caller that does not supply one renders the page without it.
  defp social_markup(document, opts) do
    case Keyword.get(opts, :base_url) do
      base_url when is_binary(base_url) and base_url != "" ->
        %{title: title, introduction: introduction, path: path} = metadata(document)

        """
        <meta property="og:title" content="#{escape(title)} · Markdow">
        <meta property="og:description" content="#{escape(introduction)}">
        <meta property="og:type" content="article">
        <meta property="og:url" content="#{escape(base_url <> path)}">
        #{MarkdowWeb.OpenGraph.meta_tags(document, base_url, Keyword.get(opts, :open_graph, []))}\
        """

      _missing ->
        ""
    end
  end

  defp provider_details(legal) do
    optional =
      [
        Keyword.get(legal, :registration),
        Keyword.get(legal, :tax_identifier)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join("<br>", &escape/1)

    optional = if optional == "", do: "", else: "<br>#{optional}"

    """
    <address>
      <strong>#{escape(Keyword.fetch!(legal, :operator_name))}</strong><br>
      #{address(legal)}<br>
      Email: <a href="mailto:#{email(legal)}">#{email(legal)}</a>#{optional}
    </address>
    """
  end

  defp address(legal) do
    legal |> Keyword.fetch!(:operator_address) |> escape() |> String.replace("\n", "<br>")
  end

  defp email(legal), do: legal |> Keyword.fetch!(:contact_email) |> escape()

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end

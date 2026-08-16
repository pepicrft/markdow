defmodule MarkdowWeb.Theme do
  @moduledoc """
  The design tokens shared by every Markdow marketing surface.

  Pages inline their own stylesheet, so the tokens are injected into each
  `<style>` block instead of being served as a separate file. A page that needs
  a different envelope overrides the token on its own root rather than writing
  a literal value, which keeps one vocabulary across the marketing pages and
  the Open Graph cards rendered from them.

  Values are grouped as surfaces, typefaces, the type scale, the spacing scale,
  rules, and layout measures. The responsive blocks restate the tokens that
  change with the viewport, so the pages themselves rarely need a breakpoint.
  """

  @tokens ~S"""
  :root {
    color-scheme: light;

    /* Surfaces and ink */
    --paper: #f8f7f2;
    --wash: #efede5;
    --ink: #24231f;
    --ink-inverted: #f5f3eb;
    --muted: #6e6b62;
    --accent: #285d4b;
    --highlight: #dce8d8;
    --rule: #cfccc2;
    --rule-inverted: #77746d;
    --positive-rule: #9cc5ae;
    --positive-ink: #b8dec7;
    --negative-rule: #e5a69a;
    --negative-ink: #f1b7ac;

    /* Typefaces */
    --serif: Charter, "Bitstream Charter", "Iowan Old Style", Georgia, serif;
    --sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    --mono: "SFMono-Regular", Consolas, "Liberation Mono", monospace;

    /* Type scale */
    --text-micro: 11px;
    --text-mini: 12px;
    --text-small: 13px;
    --text-label: 14px;
    --text-meta: 15px;
    --text-body: 16px;
    --text-root: 18px;
    --text-lead: 22px;
    --text-feature: 24px;
    --text-subheading: 25px;
    --text-heading: clamp(34px, 4vw, 50px);
    --text-title: clamp(50px, 6.2vw, 78px);

    /* Weight, leading, and tracking */
    --weight-medium: 500;
    --weight-semibold: 600;
    --weight-display: 650;
    --leading-flat: 1;
    --leading-tight: 1.08;
    --leading-snug: 1.4;
    --leading-normal: 1.55;
    --leading-loose: 1.7;
    --tracking-title: -.06em;
    --tracking-heading: -.045em;

    /* Spacing scale */
    --space-1: 4px;
    --space-2: 8px;
    --space-3: 12px;
    --space-4: 16px;
    --space-5: 20px;
    --space-6: 24px;
    --space-7: 32px;
    --space-8: 40px;
    --space-9: 48px;
    --space-10: 64px;
    --space-11: 80px;
    --space-12: 96px;
    --space-13: 112px;
    --space-14: 128px;

    /* Rules */
    --rule-width: 1px;
    --accent-width: 2px;

    /* Layout */
    --page-width: 1120px;
    --page-gutter: 48px;
    --measure-display: 780px;
    --measure-lead: 730px;
    --measure-prose: 760px;
    --measure-aside: 540px;
    --measure-label: 300px;
    --column-label: 180px;
    --column-aside: 240px;
    --column-term: 190px;
  }

  @media (max-width: 800px) {
    :root {
      --page-width: 680px;
      --page-gutter: 32px;
    }
  }

  @media (max-width: 560px) {
    :root {
      --page-width: 520px;
      --page-gutter: 24px;
      --text-root: 17px;
      --text-title: clamp(44px, 13vw, 62px);
    }
  }
  """

  @doc """
  The `:root` token declarations, ready to be inlined in a `<style>` block.
  """
  @spec tokens() :: String.t()
  def tokens, do: @tokens

  @doc """
  Replaces the `/* markdow-theme */` marker in a stylesheet with the tokens.
  """
  @spec inject(String.t()) :: String.t()
  def inject(css) when is_binary(css), do: String.replace(css, "/* markdow-theme */", @tokens)
end

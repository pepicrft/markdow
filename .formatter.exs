[
  import_deps: [:open_api_spex, :phoenix],
  plugins: [Quokka],
  quokka: [only: [:line_length]],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}"]
]

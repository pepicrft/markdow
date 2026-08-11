defmodule Markdow.Embeddings.Client do
  @moduledoc false

  alias Markdow.Embeddings.Configuration

  @callback embed(Configuration.t(), String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}
end

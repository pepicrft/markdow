defmodule Markdow.RateLimit do
  @moduledoc "The local Hammer-backed request rate limiter."

  use Hammer, backend: :ets, algorithm: :sliding_window
end

defmodule Markdow.Embeddings.Configuration do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Markdow.Embeddings.EndpointPolicy

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  # Headers the client sets from the request it is building. Letting a
  # configuration name one of these would have the credential decide the body's
  # content type or the connection's framing, which is not what it is for.
  @reserved_headers ~w(
    accept
    connection
    content-length
    content-type
    host
    proxy-connection
    te
    trailer
    transfer-encoding
    upgrade
  )

  @type t :: %__MODULE__{
          user_id: String.t(),
          endpoint: String.t(),
          model: String.t(),
          dimensions: pos_integer() | nil,
          credential_header: String.t() | nil,
          token_ciphertext: binary(),
          token_iv: binary(),
          token_tag: binary(),
          token_suffix: String.t(),
          validated_at: DateTime.t() | nil
        }

  schema "user_embedding_configurations" do
    field(:user_id, :string, primary_key: true)
    field(:endpoint, :string)
    field(:model, :string)
    field(:dimensions, :integer)
    field(:credential_header, :string)
    field(:token_ciphertext, :binary)
    field(:token_iv, :binary)
    field(:token_tag, :binary)
    field(:token_suffix, :string)
    field(:validated_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(configuration, attrs) do
    configuration
    |> cast(attrs, [
      :user_id,
      :endpoint,
      :model,
      :dimensions,
      :credential_header,
      :token_ciphertext,
      :token_iv,
      :token_tag,
      :token_suffix,
      :validated_at
    ])
    |> validate_required([
      :user_id,
      :endpoint,
      :model,
      :token_ciphertext,
      :token_iv,
      :token_tag,
      :token_suffix
    ])
    |> validate_length(:endpoint, min: 1, max: 500)
    |> validate_length(:model, min: 1, max: 200)
    |> validate_number(:dimensions, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_endpoint()
    |> validate_credential_header()
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  The header carrying the credential, and how the credential is written into it.

  `authorization` carries the `Bearer` scheme, because that is what the scheme
  belongs to. Every other header carries the credential verbatim, which is what
  the gateways using one expect. An unset header means `authorization`, so a
  configuration written before this was configurable keeps behaving the same.
  """
  @spec credential_header(t(), String.t()) :: {String.t(), String.t()}
  def credential_header(%__MODULE__{credential_header: header}, token)
      when header in [nil, "", "authorization"],
      do: {"authorization", "Bearer " <> token}

  def credential_header(%__MODULE__{credential_header: header}, token), do: {header, token}

  @doc """
  Casts a supplied header name to the single form that is stored and sent.

  The name is cast down so one header is not stored under two spellings, and is
  judged against the grammar rather than a list of names, so a value carrying a
  newline cannot append a header of its own to the request.

  Callers use this before the configuration is exercised, so the request that
  validates a configuration carries the header the stored one will carry.
  """
  @spec cast_credential_header(term()) :: {:ok, String.t() | nil} | :error
  def cast_credential_header(nil), do: {:ok, nil}

  def cast_credential_header(header) when is_binary(header) do
    normalized = header |> String.trim() |> String.downcase()

    if normalized =~ ~r/^[!#$%&'*+\-.^_`|~0-9a-z]{1,64}$/ and normalized not in @reserved_headers do
      {:ok, normalized}
    else
      :error
    end
  end

  def cast_credential_header(_header), do: :error

  defp validate_credential_header(changeset) do
    case fetch_change(changeset, :credential_header) do
      :error ->
        changeset

      {:ok, header} ->
        case cast_credential_header(header) do
          {:ok, nil} ->
            changeset

          {:ok, normalized} ->
            put_change(changeset, :credential_header, normalized)

          :error ->
            add_error(changeset, :credential_header, "is not a header the request may set")
        end
    end
  end

  # The address is checked here as well as before each request, so a refused
  # endpoint is reported as a validation error rather than reaching the wire.
  defp validate_endpoint(changeset) do
    validate_change(changeset, :endpoint, fn :endpoint, endpoint ->
      case EndpointPolicy.check(endpoint) do
        {:ok, _uri} -> []
        {:error, reason} -> [endpoint: message(reason)]
      end
    end)
  end

  defp message(:embedding_endpoint_insecure), do: "must use https"

  defp message(:embedding_endpoint_forbidden),
    do: "must not resolve to a private or loopback address"

  defp message(:embedding_endpoint_unresolvable), do: "could not be resolved"
  defp message(_reason), do: "is not a valid endpoint"
end

defmodule Markdow.Accounts do
  @moduledoc "Manages users and their vaults."

  import Ecto.Query

  alias Markdow.Accounts.EmailVerificationToken
  alias Markdow.Accounts.User
  alias Markdow.Accounts.Vault
  alias Markdow.Repo

  @default_user_id "local"
  @default_vault_id "default"

  @spec default_user_id() :: String.t()
  def default_user_id, do: @default_user_id

  @spec default_vault_id() :: String.t()
  def default_vault_id, do: @default_vault_id

  @spec list_users(module()) :: {:ok, [map()]}
  def list_users(repo \\ Repo) do
    {:ok, repo.all(from(user in User, order_by: [asc: user.email])) |> Enum.map(&user_map/1)}
  end

  @spec get_user(String.t(), module()) :: {:ok, map()} | {:error, :not_found}
  def get_user(id, repo \\ Repo) do
    case repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user_map(user)}
    end
  end

  @spec get_user_by_email(String.t(), module()) :: {:ok, map()} | {:error, :not_found}
  def get_user_by_email(email, repo \\ Repo) when is_binary(email) do
    case repo.get_by(User, email: normalize_email(email)) do
      nil -> {:error, :not_found}
      user -> {:ok, user_map(user)}
    end
  end

  @spec create_user(map(), module()) :: {:ok, map()} | {:error, term()}
  def create_user(attrs, repo \\ Repo) when is_map(attrs) do
    attrs = Map.put_new(attrs, "id", generated_id("usr"))

    %User{}
    |> User.changeset(attrs)
    |> repo.insert()
    |> map_record(&user_map/1)
  end

  @spec claim_user(String.t(), String.t(), String.t(), module()) ::
          {:ok, map()} | {:error, term()}
  def claim_user(email, name, password, repo \\ Repo)

  def claim_user(email, name, password, repo)
      when is_binary(email) and is_binary(name) and is_binary(password) do
    email = normalize_email(email)

    result =
      repo.transaction(fn ->
        email
        |> locked_user(repo)
        |> claim_locked_user(email, name, password, repo)
        |> unwrap_claim(repo)
      end)

    normalize_claim_transaction(result)
  end

  def claim_user(_email, _name, _password, _repo), do: {:error, :invalid_request}

  @spec authenticate_user(String.t(), String.t(), module()) ::
          {:ok, map()} | {:error, :invalid_credentials}
  def authenticate_user(email, password, repo \\ Repo)

  def authenticate_user(email, password, repo)
      when is_binary(email) and is_binary(password) do
    user = repo.get_by(User, email: normalize_email(email))

    if User.valid_password?(user, password),
      do: {:ok, user_map(user)},
      else: {:error, :invalid_credentials}
  end

  def authenticate_user(_email, _password, _repo) do
    User.valid_password?(nil, nil)
    {:error, :invalid_credentials}
  end

  @spec deliver_email_verification(
          map(),
          (String.t() -> String.t()),
          module(),
          module()
        ) :: {:ok, term()} | {:error, term()}
  def deliver_email_verification(
        %{id: user_id},
        build_url,
        notifier,
        repo \\ Repo
      )
      when is_binary(user_id) and is_function(build_url, 1) and is_atom(notifier) do
    with %User{} = user <- repo.get(User, user_id),
         {encoded_token, token_record} <- EmailVerificationToken.build(user),
         {_, nil} <-
           repo.delete_all(
             from(token in EmailVerificationToken, where: token.user_id == ^user_id)
           ),
         {:ok, _token} <- repo.insert(token_record),
         {:ok, email} <- notifier.deliver_verification(user, build_url.(encoded_token)) do
      {:ok, email}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_user_by_email_verification_token(String.t(), module()) ::
          {:ok, map()} | {:error, :invalid_token}
  def get_user_by_email_verification_token(token, repo \\ Repo) do
    with {:ok, query} <- EmailVerificationToken.verification_query(token),
         {%User{} = user, %EmailVerificationToken{}} <- repo.one(query) do
      {:ok, user_map(user)}
    else
      _invalid -> {:error, :invalid_token}
    end
  end

  @spec verify_user_email(String.t(), module()) ::
          {:ok, map()} | {:error, :invalid_token | term()}
  def verify_user_email(token, repo \\ Repo) do
    repo.transaction(fn -> verify_user_email_transaction(token, repo) end)
    |> normalize_verification_transaction()
  end

  @spec list_vaults(String.t(), module()) :: {:ok, [map()]} | {:error, :not_found}
  def list_vaults(user_id, repo \\ Repo) do
    with {:ok, _user} <- get_user(user_id, repo) do
      vaults =
        repo.all(from(vault in Vault, where: vault.user_id == ^user_id, order_by: vault.name))

      {:ok, Enum.map(vaults, &vault_map/1)}
    end
  end

  @spec get_vault(String.t(), module()) :: {:ok, map()} | {:error, :not_found}
  def get_vault(id, repo \\ Repo) do
    case repo.get(Vault, id) do
      nil -> {:error, :not_found}
      vault -> {:ok, vault_map(vault)}
    end
  end

  @spec create_vault(String.t(), map(), module()) :: {:ok, map()} | {:error, term()}
  def create_vault(user_id, attrs, repo \\ Repo) when is_map(attrs) do
    id = Map.get(attrs, "id") || generated_id("vlt")

    attrs =
      attrs
      |> Map.put("id", id)
      |> Map.put("user_id", user_id)
      |> Map.put("storage_prefix", "vaults/#{id}")

    %Vault{}
    |> Vault.changeset(attrs)
    |> repo.insert()
    |> map_record(&vault_map/1)
  end

  @spec storage_key(map(), String.t()) :: String.t()
  def storage_key(%{storage_prefix: ""}, note_id), do: note_id
  def storage_key(%{storage_prefix: prefix}, note_id), do: Path.join(prefix, note_id)

  defp map_record({:ok, record}, mapper), do: {:ok, mapper.(record)}
  defp map_record({:error, reason}, _mapper), do: {:error, reason}

  defp locked_user(email, repo) do
    repo.one(from(user in User, where: user.email == ^email, lock: "FOR UPDATE"))
  end

  defp claim_locked_user(nil, email, name, password, repo) do
    %User{}
    |> User.agent_signup_changeset(%{
      "id" => generated_id("usr"),
      "email" => email,
      "name" => name,
      "password" => password
    })
    |> repo.insert()
  end

  defp claim_locked_user(%User{}, _email, _name, _password, _repo) do
    Argon2.no_user_verify()
    {:error, :account_exists}
  end

  defp unwrap_claim({:ok, claimed_user}, _repo), do: user_map(claimed_user)
  defp unwrap_claim({:error, reason}, repo), do: repo.rollback(reason)

  defp normalize_claim_transaction({:ok, user}), do: {:ok, user}
  defp normalize_claim_transaction({:error, reason}), do: {:error, reason}

  defp user_map(user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      email_verified_at: user.email_verified_at,
      created_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end

  defp vault_map(vault) do
    %{
      id: vault.id,
      user_id: vault.user_id,
      name: vault.name,
      storage_prefix: vault.storage_prefix,
      created_at: vault.inserted_at,
      updated_at: vault.updated_at
    }
  end

  defp generated_id(prefix) do
    suffix = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    "#{prefix}_#{suffix}"
  end

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

  defp verify_user_email_transaction(token, repo) do
    with {:ok, query} <- EmailVerificationToken.verification_query(token),
         {%User{} = user, %EmailVerificationToken{}} <-
           repo.one(from(record in query, lock: "FOR UPDATE")),
         {:ok, user} <-
           user
           |> Ecto.Changeset.change(
             email_verified_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
           )
           |> repo.update() do
      repo.delete_all(from(record in EmailVerificationToken, where: record.user_id == ^user.id))
      user_map(user)
    else
      _invalid -> repo.rollback(:invalid_token)
    end
  end

  defp normalize_verification_transaction({:ok, user}), do: {:ok, user}
  defp normalize_verification_transaction({:error, reason}), do: {:error, reason}
end

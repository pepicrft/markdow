defmodule Markdow.Secrets do
  @moduledoc "Encrypts provider credentials before they are stored."

  @iv_bytes 12

  @spec encrypt(String.t(), binary() | nil, String.t()) :: {:ok, map()} | {:error, atom()}
  def encrypt(value, key, context)
      when is_binary(value) and byte_size(value) > 0 and is_binary(key) and byte_size(key) == 32 do
    iv = :crypto.strong_rand_bytes(@iv_bytes)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, value, aad(context), true)

    {:ok, %{token_ciphertext: ciphertext, token_iv: iv, token_tag: tag}}
  end

  def encrypt(_value, _key, _context), do: {:error, :embedding_secret_key_unavailable}

  @spec decrypt(map(), binary() | nil, String.t()) :: {:ok, String.t()} | {:error, atom()}
  def decrypt(configuration, key, context) when is_binary(key) and byte_size(key) == 32 do
    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           key,
           configuration.token_iv,
           configuration.token_ciphertext,
           aad(context),
           configuration.token_tag,
           false
         ) do
      :error -> {:error, :embedding_secret_invalid}
      value -> {:ok, value}
    end
  end

  def decrypt(_configuration, _key, _context),
    do: {:error, :embedding_secret_key_unavailable}

  defp aad(context), do: "markdow:embedding:#{context}"
end

defmodule PulumiViewer.HostCredentials do
  @moduledoc """
  Credentials from a host credential helper: `AWS_CONTAINER_CREDENTIALS_FULL_URI` with the token
  in `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE`, ECS JSON format (`AccessKeyId`, `SecretAccessKey`,
  `Token`, `Expiration`). Used for profiles ExAws cannot read, such as `aws login`.

  Keys are cached until 60 s before `Expiration` and fetched again on the next request. A helper
  that does not answer gives `{:error, :credential_helper}`; nothing crashes (ExAws's own
  `:pod_identity` source raises inside its AuthCache and can stop the `:ex_aws` application).
  """
  use GenServer

  @table __MODULE__
  @lead_s 60
  # when the helper sends no Expiration
  @default_ttl_s 900

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  def configured? do
    present?("AWS_CONTAINER_CREDENTIALS_FULL_URI") and
      present?("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE")
  end

  @doc "Keys for an ExAws request: `access_key_id`, `secret_access_key`, `security_token`."
  def fetch do
    now = System.os_time(:second)

    case :ets.lookup(@table, :keys) do
      [{:keys, keys, exp}] when exp - now > @lead_s -> {:ok, keys}
      _ -> refresh(now)
    end
  end

  def clear, do: :ets.delete_all_objects(@table)

  defp refresh(now) do
    with {:ok, token} <- File.read(System.get_env("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE")),
         {:ok, %Req.Response{status: 200, body: body}} <-
           Req.get(System.get_env("AWS_CONTAINER_CREDENTIALS_FULL_URI"),
             headers: [{"authorization", String.trim(token)}],
             receive_timeout: 5_000,
             connect_options: [timeout: 2_000],
             retry: false,
             decode_body: false
           ),
         {:ok, %{"AccessKeyId" => id, "SecretAccessKey" => secret} = c} <- Jason.decode(body) do
      keys = [access_key_id: id, secret_access_key: secret, security_token: c["Token"]]
      :ets.insert(@table, {:keys, keys, expiration(c["Expiration"], now)})
      {:ok, keys}
    else
      _ -> {:error, :credential_helper}
    end
  rescue
    _ -> {:error, :credential_helper}
  catch
    :exit, _ -> {:error, :credential_helper}
  end

  defp expiration(iso, now) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> now + @default_ttl_s
    end
  end

  defp expiration(_, now), do: now + @default_ttl_s

  defp present?(var), do: System.get_env(var) not in [nil, ""]
end

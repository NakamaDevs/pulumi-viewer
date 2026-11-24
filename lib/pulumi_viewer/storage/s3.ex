defmodule PulumiViewer.Storage.S3 do
  @behaviour PulumiViewer.Storage

  @impl true
  def list(%{bucket: bucket} = cfg, prefix) do
    bucket
    |> ExAws.S3.list_objects_v2(prefix: full(cfg, prefix))
    |> ExAws.stream!(aws_opts(cfg))
    |> Enum.map(&strip(cfg, &1.key))
  end

  @impl true
  def read(%{bucket: bucket} = cfg, key) do
    case ExAws.S3.get_object(bucket, full(cfg, key)) |> ExAws.request(aws_opts(cfg)) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, e} -> {:error, e}
    end
  end

  defp full(%{prefix: nil}, key), do: key
  defp full(%{prefix: p}, key), do: p <> "/" <> key

  defp strip(%{prefix: nil}, key), do: key
  defp strip(%{prefix: p}, key), do: String.replace_prefix(key, p <> "/", "")

  # Honour AWS_ENDPOINT_URL so the same code reads Floci, LocalStack or the AWS Emulator.
  # A source with `?profile=` uses only that profile: never fall back to other credentials,
  # which would read this source with another account's keys. Without a profile, the same
  # precedence as CloudFormation: keys in the environment win, then the host credential helper
  # when configured, else the default ExAws chain.
  defp aws_opts(%{profile: p}) when is_binary(p) do
    case PulumiViewer.AwsCredentials.opts(p) do
      {:ok, creds} -> creds ++ endpoint_opts()
      {:error, e} -> raise e
    end
  end

  defp aws_opts(_cfg), do: host_credentials() ++ endpoint_opts()

  defp host_credentials do
    if PulumiViewer.CloudFormation.Client.credential_source() == :container_full_uri do
      case PulumiViewer.HostCredentials.fetch() do
        {:ok, keys} ->
          keys

        _ ->
          raise "The host credential helper did not answer. Run `aws login --profile bundle-readonly` on the host."
      end
    else
      []
    end
  end

  defp endpoint_opts do
    case System.get_env("AWS_ENDPOINT_URL_S3") || System.get_env("AWS_ENDPOINT_URL") do
      nil ->
        []

      url ->
        u = URI.parse(url)
        [scheme: u.scheme <> "://", host: u.host, port: u.port, virtual_host: false]
    end
  end
end

defmodule PulumiViewer.Storage.S3 do
  @behaviour PulumiViewer.Storage

  @impl true
  def list(%{bucket: bucket} = cfg, prefix) do
    bucket
    |> ExAws.S3.list_objects_v2(prefix: full(cfg, prefix))
    |> ExAws.stream!(aws_opts())
    |> Enum.map(&strip(cfg, &1.key))
  end

  @impl true
  def read(%{bucket: bucket} = cfg, key) do
    case ExAws.S3.get_object(bucket, full(cfg, key)) |> ExAws.request(aws_opts()) do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, e} -> {:error, e}
    end
  end

  defp full(%{prefix: nil}, key), do: key
  defp full(%{prefix: p}, key), do: p <> "/" <> key

  defp strip(%{prefix: nil}, key), do: key
  defp strip(%{prefix: p}, key), do: String.replace_prefix(key, p <> "/", "")

  # Honour AWS_ENDPOINT_URL so the same code reads Floci, LocalStack or the AWS Emulator.
  defp aws_opts, do: host_credentials() ++ endpoint_opts()

  defp host_credentials do
    if PulumiViewer.HostCredentials.configured?() do
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

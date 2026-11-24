defmodule PulumiViewer.Storage do
  @moduledoc """
  Read-only access to a Pulumi DIY backend. The URL uses the same form as
  `pulumi login`: `file://<dir>` or `s3://<bucket>[/<prefix>]`. For an AWS
  emulator (Floci, LocalStack, AWS Emulator) set `AWS_ENDPOINT_URL`.

  `cloudformation://<region>[?prefix=<p>]` is not a Pulumi backend: it reads live
  CloudFormation stacks instead (see `PulumiViewer.CloudFormation`).
  """

  @callback list(config :: term, prefix :: String.t()) :: [String.t()]
  @callback read(config :: term, key :: String.t()) :: {:ok, binary} | {:error, term}

  def parse_url("file://" <> path),
    do: {PulumiViewer.Storage.Local, Path.expand(path) |> relative(path)}

  def parse_url("s3://" <> rest) do
    [bucket | prefix] = rest |> String.split("?") |> hd() |> String.split("/", parts: 2)
    {PulumiViewer.Storage.S3, %{bucket: bucket, prefix: prefix |> List.first() |> blank()}}
  end

  def parse_url("cloudformation://" <> rest),
    do: {PulumiViewer.CloudFormation, PulumiViewer.CloudFormation.parse_url(rest)}

  # tests register extra schemes (see test/support/failing_storage.ex)
  def parse_url(url) do
    [scheme | _] = String.split(url, "://", parts: 2)

    case Application.get_env(:pulumi_viewer, :test_backends, %{})[scheme] do
      nil -> raise ArgumentError, "unknown source URL #{inspect(url)}"
      backend -> backend
    end
  end

  @doc "The backend of one source (see `PulumiViewer.Sources`)."
  def for_source(%{url: url}), do: parse_url(url)

  def list({mod, cfg}, prefix), do: mod.list(cfg, prefix)
  def read({mod, cfg}, key), do: mod.read(cfg, key)

  # keep relative paths relative so tests and `file://.` behave like the Pulumi CLI
  defp relative(_expanded, "~" <> _ = path), do: Path.expand(path)
  defp relative(expanded, path), do: if(Path.type(path) == :relative, do: path, else: expanded)

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(p), do: String.trim(p, "/")
end

defmodule PulumiViewer.Storage do
  @moduledoc """
  Read-only access to a Pulumi DIY backend. The URL uses the same form as
  `pulumi login`: `file://<dir>` or `s3://<bucket>[/<prefix>]`. For an AWS
  emulator (Floci, LocalStack, AWS Emulator) set `AWS_ENDPOINT_URL`.
  """

  @callback list(config :: term, prefix :: String.t()) :: [String.t()]
  @callback read(config :: term, key :: String.t()) :: {:ok, binary} | {:error, term}

  def parse_url("file://" <> path),
    do: {PulumiViewer.Storage.Local, Path.expand(path) |> relative(path)}

  def parse_url("s3://" <> rest) do
    [bucket | prefix] = rest |> String.split("?") |> hd() |> String.split("/", parts: 2)
    {PulumiViewer.Storage.S3, %{bucket: bucket, prefix: prefix |> List.first() |> blank()}}
  end

  def current, do: parse_url(Application.fetch_env!(:pulumi_viewer, :backend_url))

  def list(prefix) do
    {mod, cfg} = current()
    mod.list(cfg, prefix)
  end

  def read(key) do
    {mod, cfg} = current()
    mod.read(cfg, key)
  end

  # keep relative paths relative so tests and `file://.` behave like the Pulumi CLI
  defp relative(_expanded, "~" <> _ = path), do: Path.expand(path)
  defp relative(expanded, path), do: if(Path.type(path) == :relative, do: path, else: expanded)

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(p), do: String.trim(p, "/")
end

defmodule PulumiViewer.Storage do
  @moduledoc """
  The sources the viewer reads. A source is a Pulumi DIY backend, in the same form as
  `pulumi login` (`file://<dir>` or `s3://<bucket>[/<prefix>]`), or live CloudFormation stacks
  (`cloudformation://<region>[?prefix=<p>]`, see `PulumiViewer.CloudFormation`). For an AWS
  emulator (Floci, LocalStack, AWS Emulator) set `AWS_ENDPOINT_URL`.

  Several sources load at the same time: `PULUMI_BACKEND_URLS="dev=cloudformation://us-east-1,
  prod=s3://state-prod"`. Each AWS source can name its own profile with `?profile=<name>`.
  A single `PULUMI_BACKEND_URL` is one source named `default`.
  """

  @callback list(config :: term, prefix :: String.t()) :: [String.t()]
  @callback read(config :: term, key :: String.t()) :: {:ok, binary} | {:error, term}

  def parse_url("file://" <> path),
    do: {PulumiViewer.Storage.Local, Path.expand(path) |> relative(path)}

  def parse_url("s3://" <> rest) do
    {path, query} = split_query(rest)
    [bucket | prefix] = String.split(path, "/", parts: 2)

    {PulumiViewer.Storage.S3,
     %{
       bucket: bucket,
       prefix: prefix |> List.first() |> blank(),
       profile: blank(query["profile"])
     }}
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

  @doc """
  The backend of one source (see `PulumiViewer.Sources`). The source name goes into an AWS
  config: it keys the CloudFormation cache, because two sources can read the same region
  with different profiles.
  """
  def for_source(%{name: name, url: url}) do
    case parse_url(url) do
      {mod, cfg} when is_map(cfg) -> {mod, Map.put(cfg, :name, name)}
      other -> other
    end
  end

  def list({mod, cfg}, prefix), do: mod.list(cfg, prefix)
  def read({mod, cfg}, key), do: mod.read(cfg, key)

  defp split_query(rest) do
    case String.split(rest, "?", parts: 2) do
      [path, q] -> {path, URI.decode_query(q)}
      [path] -> {path, %{}}
    end
  end

  # keep relative paths relative so tests and `file://.` behave like the Pulumi CLI
  defp relative(_expanded, "~" <> _ = path), do: Path.expand(path)
  defp relative(expanded, path), do: if(Path.type(path) == :relative, do: path, else: expanded)

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(p), do: String.trim(p, "/")
end

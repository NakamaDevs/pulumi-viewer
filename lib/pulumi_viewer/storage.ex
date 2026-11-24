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

  @doc "All sources, in the configured order: `[%{name, url, mod, cfg}]`."
  def sources do
    named_urls()
    |> Enum.map(fn {name, url} ->
      {mod, cfg} = parse_url(url)
      %{name: name, url: url, mod: mod, cfg: with_name(cfg, name)}
    end)
  end

  @doc "The source with this name; the first source when the name is nil or empty."
  def source(name) when name in [nil, ""], do: hd(sources())
  def source(name), do: Enum.find(sources(), &(&1.name == name))

  def list(%{mod: mod, cfg: cfg}, prefix), do: mod.list(cfg, prefix)
  def read(%{mod: mod, cfg: cfg}, key), do: mod.read(cfg, key)

  defp named_urls do
    case Application.get_env(:pulumi_viewer, :backend_urls) do
      list when is_binary(list) and list != "" ->
        list
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.with_index(1)
        |> Enum.map(fn {entry, i} ->
          case String.split(entry, "=", parts: 2) do
            [name, url] ->
              if String.contains?(name, "://"), do: {"source#{i}", entry}, else: {name, url}

            [url] ->
              {"source#{i}", url}
          end
        end)

      _ ->
        [{"default", Application.fetch_env!(:pulumi_viewer, :backend_url)}]
    end
  end

  # the name keys the cache and the credentials of AWS sources; a file source is just a path
  defp with_name(cfg, name) when is_map(cfg), do: Map.put(cfg, :name, name)
  defp with_name(cfg, _name), do: cfg

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

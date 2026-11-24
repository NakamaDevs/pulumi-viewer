defmodule PulumiViewer.Sources do
  @moduledoc """
  The sources the viewer reads. `PULUMI_VIEWER_SOURCES` holds one `name=url` entry per line
  or `;`-separated, for example
  `pulumi=file:///state/pulumi;cloudformation=cloudformation://us-east-1`.
  Without it, `PULUMI_BACKEND_URL` is one source named `default`.
  """

  @type t :: %{name: String.t(), url: String.t(), kind: :pulumi | :cloudformation}

  @doc "All configured sources, in the configured order."
  def all do
    resolve(
      Application.get_env(:pulumi_viewer, :sources),
      Application.get_env(:pulumi_viewer, :backend_url)
    )
  end

  @doc "The source with this name, or the first one for `nil`."
  def fetch(nil), do: {:ok, hd(all())}

  def fetch(name) do
    case Enum.find(all(), &(&1.name == name)) do
      nil -> {:error, :unknown_source}
      s -> {:ok, s}
    end
  end

  def resolve(sources, _backend_url) when is_binary(sources) and sources != "", do: parse(sources)
  def resolve(_, url) when is_binary(url), do: [entry("default", url)]
  def resolve(_, _), do: []

  def parse(text) do
    entries =
      text
      |> String.split(["\n", ";"], trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn e ->
        case String.split(e, "=", parts: 2) do
          [name, url] when name != "" ->
            if String.contains?(name, "://"),
              do: bad(e),
              else: entry(String.trim(name), String.trim(url))

          _ ->
            bad(e)
        end
      end)

    case entries -- Enum.uniq_by(entries, & &1.name) do
      [] -> entries
      [dup | _] -> raise ArgumentError, "PULUMI_VIEWER_SOURCES names the source #{dup.name} twice"
    end
  end

  defp bad(e),
    do: raise(ArgumentError, "PULUMI_VIEWER_SOURCES entry #{inspect(e)} is not name=url")

  defp entry(name, url), do: %{name: name, url: url, kind: kind(url)}

  defp kind("cloudformation://" <> _), do: :cloudformation
  defp kind("file://" <> _), do: :pulumi
  defp kind("s3://" <> _), do: :pulumi

  defp kind(url),
    do:
      raise(
        ArgumentError,
        "unknown source URL #{inspect(url)}: use file://, s3:// or cloudformation://"
      )
end

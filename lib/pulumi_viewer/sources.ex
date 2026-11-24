defmodule PulumiViewer.Sources do
  @moduledoc """
  The sources the viewer reads. `PULUMI_VIEWER_SOURCES` (or its older name
  `PULUMI_BACKEND_URLS`) holds `name=url` entries separated by a newline, `;` or `,`, for example
  `pulumi=file:///state/pulumi;cloudformation=cloudformation://us-east-1`.

  - A `,` starts a new entry only before `name=scheme://` or `scheme://`, so a comma inside a
    query value (`?prefix=a,b`) stays. Stray commas and spaces around an entry are ignored.
  - A bare URL without a name (the old `PULUMI_BACKEND_URLS` form) is named `source<i>`, where
    `i` is its 1-based position in the list.
  - An `s3://` or `cloudformation://` source can name its own AWS profile with
    `?profile=<name>`; it then uses only that profile.
  - Without entries (unset, empty, or only separators), `PULUMI_BACKEND_URL` is one source
    named `default`.

  A malformed entry, an unknown URL scheme, a duplicate name or no source at all stops startup.
  """

  @type t :: %{name: String.t(), url: String.t(), kind: :pulumi | :cloudformation}

  @doc "All configured sources, in the configured order."
  def all do
    resolve(
      Application.get_env(:pulumi_viewer, :sources),
      Application.get_env(:pulumi_viewer, :backend_url)
    )
  end

  @doc "Checks the configuration at startup, so a bad entry stops the app with a clear message."
  def validate! do
    case all() do
      [] ->
        raise ArgumentError,
              "no sources: set PULUMI_VIEWER_SOURCES (name=url entries) or PULUMI_BACKEND_URL"

      sources ->
        sources
    end
  end

  @doc "The source with this name, or the first one for `nil`."
  def fetch(nil) do
    case all() do
      [s | _] -> {:ok, s}
      [] -> {:error, :unknown_source}
    end
  end

  def fetch(name) do
    case Enum.find(all(), &(&1.name == name)) do
      nil -> {:error, :unknown_source}
      s -> {:ok, s}
    end
  end

  def resolve(sources, url) when is_binary(sources) do
    case parse(sources) do
      [] -> resolve(nil, url)
      entries -> entries
    end
  end

  def resolve(_, url) when is_binary(url), do: [entry("default", url)]
  def resolve(_, _), do: []

  @url ~r/^[a-z][a-z0-9+.-]*:\/\//i

  def parse(text) do
    entries =
      text
      # a comma splits only where a new `name=scheme://` or `scheme://` entry starts, so
      # `?prefix=a,b` stays
      |> String.split(~r/[\n;]|,(?=\s*(?:[^,;=\s]+\s*=\s*)?[a-z][a-z0-9+.-]*:\/\/)/i, trim: true)
      # stray separators: `a=s3://bucket,` is bucket `bucket`
      |> Enum.map(&String.replace(&1, ~r/^[\s,]+|[\s,]+$/, ""))
      |> Enum.reject(&(&1 == ""))
      |> Enum.with_index(1)
      |> Enum.map(fn {e, i} ->
        if Regex.match?(@url, e), do: entry("source#{i}", e), else: named(e)
      end)

    case entries -- Enum.uniq_by(entries, & &1.name) do
      [] -> entries
      [dup | _] -> raise ArgumentError, "PULUMI_VIEWER_SOURCES names the source #{dup.name} twice"
    end
  end

  defp named(e) do
    case String.split(e, "=", parts: 2) do
      [name, url] when name != "" ->
        if String.contains?(name, "://"),
          do: bad(e),
          else: entry(String.trim(name), String.trim(url))

      _ ->
        bad(e)
    end
  end

  defp bad(e),
    do: raise(ArgumentError, "PULUMI_VIEWER_SOURCES entry #{inspect(e)} is not name=url")

  defp entry(name, url), do: %{name: name, url: url, kind: kind(url)}

  defp kind("cloudformation://" <> _), do: :cloudformation
  defp kind("file://" <> _), do: :pulumi
  defp kind("s3://" <> _), do: :pulumi

  defp kind(url) do
    [scheme | _] = String.split(url, "://", parts: 2)

    if Map.has_key?(Application.get_env(:pulumi_viewer, :test_backends, %{}), scheme),
      do: :pulumi,
      else: unknown(url)
  end

  defp unknown(url),
    do:
      raise(
        ArgumentError,
        "unknown source URL #{inspect(url)}: use file://, s3:// or cloudformation://"
      )
end

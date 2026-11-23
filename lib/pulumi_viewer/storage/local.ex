defmodule PulumiViewer.Storage.Local do
  @behaviour PulumiViewer.Storage

  @impl true
  def list(root, prefix) do
    base = Path.join(root, prefix)

    Path.wildcard(Path.join(base, "**"), match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.sort()
  end

  @impl true
  def read(root, key), do: File.read(Path.join(root, key))
end

defmodule PulumiViewer.FailingStorage do
  @moduledoc "A test backend (`raise://` or `exit://`) that crashes the way a broken S3 client can."
  @behaviour PulumiViewer.Storage

  @impl true
  def list(:raise, _), do: raise(ArgumentError, "boom")
  def list(:exit, _), do: exit(:noproc)
  def list(:read_raises, _), do: [".pulumi/stacks/bundle/dev.json"]

  @impl true
  def read(_, _), do: raise(ArgumentError, "read boom")
end

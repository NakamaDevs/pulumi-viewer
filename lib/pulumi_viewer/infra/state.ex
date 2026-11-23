defmodule PulumiViewer.Infra.State do
  @moduledoc false
  alias PulumiViewer.Pulumi.{Checkpoint, History, Layout}
  alias PulumiViewer.Storage

  def stacks do
    Storage.list(".pulumi/stacks/") |> Layout.stacks()
  end

  def checkpoint(project, stack) do
    case Enum.find(stacks(), &(&1.project == blank(project) and &1.stack == stack)) do
      nil -> {:error, :not_found}
      %{key: key} -> with {:ok, body} <- Storage.read(key), do: Checkpoint.parse(body)
    end
  end

  def updates(project, stack, limit \\ 50) do
    Layout.history_prefix(blank(project), stack)
    |> Storage.list()
    |> Layout.history_keys()
    |> Enum.take(limit)
    |> Enum.flat_map(fn key ->
      with {:ok, body} <- Storage.read(key),
           {:ok, u} <- History.parse(body),
           do: [u],
           else: (_ -> [])
    end)
  end

  defp blank(""), do: nil
  defp blank(v), do: v
end

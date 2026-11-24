defmodule PulumiViewer.Infra.State do
  @moduledoc false
  alias PulumiViewer.{CloudFormation, Storage}
  alias PulumiViewer.Pulumi.{Checkpoint, History, Layout}

  # Every function takes a source name; nil means the first source.
  def stacks(source_name) do
    case Storage.source(source_name) do
      nil -> {:error, :unknown_source}
      %{mod: CloudFormation, cfg: cfg} -> CloudFormation.stacks(cfg)
      src -> {:ok, Storage.list(src, ".pulumi/stacks/") |> Layout.stacks()}
    end
  end

  def checkpoint(source_name, project, stack) do
    case Storage.source(source_name) do
      nil ->
        {:error, :not_found}

      %{mod: CloudFormation, cfg: cfg} ->
        CloudFormation.checkpoint(cfg, stack)

      src ->
        {:ok, stacks} = stacks(source_name)

        case Enum.find(stacks, &(&1.project == blank(project) and &1.stack == stack)) do
          nil -> {:error, :not_found}
          %{key: key} -> with {:ok, body} <- Storage.read(src, key), do: Checkpoint.parse(body)
        end
    end
  end

  def updates(source_name, project, stack, limit \\ 50) do
    case Storage.source(source_name) do
      nil -> []
      %{mod: CloudFormation, cfg: cfg} -> CloudFormation.updates(cfg, stack, limit)
      src -> pulumi_updates(src, project, stack, limit)
    end
  end

  defp pulumi_updates(src, project, stack, limit) do
    Layout.history_prefix(blank(project), stack)
    |> then(&Storage.list(src, &1))
    |> Layout.history_keys()
    |> Enum.take(limit)
    |> Enum.flat_map(fn key ->
      with {:ok, body} <- Storage.read(src, key),
           {:ok, u} <- History.parse(body),
           do: [u],
           else: (_ -> [])
    end)
  end

  defp blank(""), do: nil
  defp blank(v), do: v
end

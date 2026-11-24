defmodule PulumiViewer.Infra.State do
  @moduledoc false
  alias PulumiViewer.{CloudFormation, Storage}
  alias PulumiViewer.Pulumi.{Checkpoint, History, Layout}

  def stacks do
    case Storage.current() do
      {CloudFormation, cfg} -> CloudFormation.stacks(cfg)
      _ -> {:ok, Storage.list(".pulumi/stacks/") |> Layout.stacks()}
    end
  end

  def checkpoint(project, stack) do
    case Storage.current() do
      {CloudFormation, cfg} ->
        CloudFormation.checkpoint(cfg, stack)

      _ ->
        {:ok, stacks} = stacks()

        case Enum.find(stacks, &(&1.project == blank(project) and &1.stack == stack)) do
          nil -> {:error, :not_found}
          %{key: key} -> with {:ok, body} <- Storage.read(key), do: Checkpoint.parse(body)
        end
    end
  end

  def updates(project, stack, limit \\ 50) do
    case Storage.current() do
      {CloudFormation, cfg} -> CloudFormation.updates(cfg, stack, limit)
      _ -> pulumi_updates(project, stack, limit)
    end
  end

  defp pulumi_updates(project, stack, limit) do
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

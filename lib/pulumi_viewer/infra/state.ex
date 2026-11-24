defmodule PulumiViewer.Infra.State do
  @moduledoc """
  Reads stacks, checkpoints and updates of one source. Pulumi state is read again on each call
  (resources move between stacks during the day); CloudFormation calls have a 60 s cache.
  """
  alias PulumiViewer.{CloudFormation, Sources, Storage}
  alias PulumiViewer.Pulumi.{Checkpoint, History, Layout}

  @doc "A source map, or a source name (`nil` is the first source)."
  def source(%{url: _} = s), do: {:ok, s}
  def source(name), do: Sources.fetch(name)

  def stacks(src) do
    with {:ok, s} <- source(src) do
      case Storage.for_source(s) do
        {CloudFormation, cfg} ->
          CloudFormation.stacks(cfg)

        backend ->
          safe(fn -> {:ok, Storage.list(backend, ".pulumi/stacks/") |> Layout.stacks()} end)
      end
    end
  end

  def checkpoint(src, project, stack) do
    with {:ok, s} <- source(src) do
      case Storage.for_source(s) do
        {CloudFormation, cfg} ->
          CloudFormation.checkpoint(cfg, stack)

        backend ->
          with {:ok, stacks} <- stacks(s) do
            case Enum.find(stacks, &(&1.project == blank(project) and &1.stack == stack)) do
              nil ->
                {:error, :not_found}

              %{key: key} ->
                with {:ok, body} <- Storage.read(backend, key), do: Checkpoint.parse(body)
            end
          end
      end
    end
  end

  def updates(src, project, stack, limit \\ 50) do
    case source(src) do
      {:ok, s} ->
        case Storage.for_source(s) do
          {CloudFormation, cfg} -> CloudFormation.updates(cfg, stack, limit)
          backend -> pulumi_updates(backend, project, stack, limit)
        end

      _ ->
        []
    end
  end

  defp pulumi_updates(backend, project, stack, limit) do
    Layout.history_prefix(blank(project), stack)
    |> then(&Storage.list(backend, &1))
    |> Layout.history_keys()
    |> Enum.take(limit)
    |> Enum.flat_map(fn key ->
      with {:ok, body} <- Storage.read(backend, key),
           {:ok, u} <- History.parse(body),
           do: [u],
           else: (_ -> [])
    end)
  end

  # An S3 source with no access or a missing folder raises; show it as this source's error.
  defp safe(fun) do
    fun.()
  rescue
    e ->
      {:error, %CloudFormation.Error{message: "Cannot read the state: " <> Exception.message(e)}}
  end

  defp blank(""), do: nil
  defp blank(v), do: v
end

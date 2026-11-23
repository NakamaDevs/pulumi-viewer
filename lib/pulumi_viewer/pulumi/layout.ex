defmodule PulumiViewer.Pulumi.Layout do
  @moduledoc """
  Key layout of a Pulumi DIY (self-managed) backend.

  Project-scoped stacks live at `.pulumi/stacks/<project>/<stack>.json[.gz]`,
  legacy stacks at `.pulumi/stacks/<stack>.json[.gz]`. Update history lives at
  `.pulumi/history/<project>/<stack>/<stack>-<unix-nanos>.history.json`.
  """

  @stack_re ~r{^\.pulumi/stacks/(?:(?<project>[^/]+)/)?(?<stack>[^/]+)\.json(?:\.gz)?$}

  @spec stacks([String.t()]) :: [%{project: String.t() | nil, stack: String.t(), key: String.t()}]
  def stacks(keys) do
    keys
    |> Enum.flat_map(fn key ->
      case Regex.named_captures(@stack_re, key) do
        %{"project" => p, "stack" => s} -> [%{project: blank_to_nil(p), stack: s, key: key}]
        nil -> []
      end
    end)
    |> Enum.sort_by(&{&1.project == nil, &1.project, &1.stack})
  end

  def history_prefix(nil, stack), do: ".pulumi/history/#{stack}/"
  def history_prefix(project, stack), do: ".pulumi/history/#{project}/#{stack}/"

  @doc "History files only (not checkpoint copies), newest first."
  def history_keys(keys) do
    keys
    |> Enum.filter(&String.ends_with?(&1, ".history.json"))
    |> Enum.sort_by(&timestamp/1, :desc)
  end

  defp timestamp(key) do
    case Regex.run(~r/-(\d+)\.history\.json$/, key) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
end

defmodule PulumiViewer.CLI do
  @moduledoc """
  Read-only command line for the safety checks. Prints JSON.

      checks [--source NAME] [--stack PROJECT/STACK] [--min error|warning|info]
      flags  --stack PROJECT/STACK [--source NAME]

  In the container: `bin/checks checks --min warning` (runs in the live node). In a checkout:
  `mix pv checks`. Exit status 1 when a finding at `--min` or above exists (checks only).
  """
  alias PulumiViewer.Checks

  def main(args) do
    {code, out} = run(args)
    IO.puts(Jason.encode!(out, pretty: true))
    code
  end

  @doc "{exit code, JSON-ready map}"
  def run(args) do
    {opts, cmd, _} =
      OptionParser.parse(args, strict: [source: :string, stack: :string, min: :string])

    case cmd do
      ["checks"] ->
        checks(opts)

      ["flags"] ->
        flags(opts)

      _ ->
        {2, %{error: "usage: checks|flags [--source NAME] [--stack PROJECT/STACK] [--min LEVEL]"}}
    end
  end

  @doc "Every Pulumi stack of the sources, or the one stack in `opts`, with its findings."
  def checks(opts) do
    min = rank(opts[:min] || "info")
    links = PulumiViewer.Infra.Links.index(:pulumi)

    stacks =
      for {src, project, stack} <- stacks(opts) do
        case Checks.for_stack(src, project, stack, links) do
          {:ok, %{findings: fs}} ->
            %{
              source: src,
              project: project,
              stack: stack,
              findings: Enum.filter(fs, &(rank(&1.severity) <= min))
            }

          {:error, e} ->
            %{source: src, project: project, stack: stack, error: PulumiViewer.error_message(e)}
        end
      end

    bad = Enum.any?(stacks, &(Map.get(&1, :findings, []) != []))
    {if(bad, do: 1, else: 0), %{stacks: stacks}}
  end

  def flags(opts) do
    case stacks(opts) do
      [{src, project, stack}] ->
        case Checks.for_stack(src, project, stack) do
          {:ok, %{resources: rs}} ->
            {0, %{source: src, project: project, stack: stack, resources: rs}}

          {:error, e} ->
            {1, %{error: PulumiViewer.error_message(e)}}
        end

      _ ->
        {2, %{error: "flags needs one --stack PROJECT/STACK"}}
    end
  end

  defp stacks(opts) do
    sources =
      PulumiViewer.Sources.all()
      |> Enum.filter(&(&1.kind == :pulumi and opts[:source] in [nil, &1.name]))

    want = opts[:stack] && String.split(opts[:stack], "/", parts: 2)

    for s <- sources,
        {:ok, list} <- [PulumiViewer.Infra.State.stacks(s)],
        st <- list,
        want in [nil, [st.project || "", st.stack], [st.stack]],
        do: {s.name, st.project, st.stack}
  end

  defp rank(l) when l in [:error, "error"], do: 0
  defp rank(l) when l in [:warning, "warning"], do: 1
  defp rank(_), do: 2
end

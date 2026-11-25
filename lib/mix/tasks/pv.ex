defmodule Mix.Tasks.Pv do
  @shortdoc "Read-only safety checks of Pulumi state (see PulumiViewer.CLI)"
  @moduledoc @shortdoc
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ex_aws)
    {:ok, _} = Task.Supervisor.start_link(name: PulumiViewer.TaskSupervisor)
    code = PulumiViewer.CLI.main(args)
    if code != 0, do: exit({:shutdown, code})
  end
end

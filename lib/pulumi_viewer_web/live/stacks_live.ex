defmodule PulumiViewerWeb.StacksLive do
  use PulumiViewerWeb, :live_view
  alias PulumiViewer.{Environment, Sources}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Stacks", env: "all", source: "all") |> load()}
  end

  @impl true
  def handle_event("refresh", _, socket), do: {:noreply, load(socket)}

  def handle_event("filter", params, socket),
    do:
      {:noreply,
       assign(socket,
         env: params["env"] || socket.assigns.env,
         source: params["source"] || socket.assigns.source
       )}

  # Each source loads on its own, so one failing source does not hide the others.
  defp load(socket) do
    results =
      Task.Supervisor.async_stream_nolink(
        PulumiViewer.TaskSupervisor,
        Sources.all(),
        fn s ->
          case PulumiViewer.Infra.list_stacks(s.name) do
            {:ok, stacks} -> {s, {:ok, stacks}}
            {:error, e} -> {s, {:error, PulumiViewer.error_message(e)}}
          end
        end,
        max_concurrency: 4,
        timeout: 120_000,
        on_timeout: :kill_task
      )
      |> Enum.zip(Sources.all())
      |> Enum.map(fn
        {{:ok, r}, _} -> r
        {{:exit, :timeout}, s} -> {s, {:error, "Timed out while reading this source."}}
        {{:exit, reason}, s} -> {s, {:error, "Read failed: #{inspect(reason)}"}}
      end)

    assign(socket, results: results)
  end

  @doc false
  # [{group, [{source_name, [{project, [stack]}]}]}], environments first, then "Account-wide"
  def grouped(stacks) do
    stacks
    |> Enum.group_by(&group/1)
    |> Enum.sort_by(fn {g, _} -> group_sort(g) end)
    |> Enum.map(fn {g, in_group} ->
      by_source =
        in_group
        |> Enum.group_by(& &1.source)
        |> Enum.sort()
        |> Enum.map(fn {src, ss} ->
          {src,
           ss
           |> Enum.group_by(&(&1.project || "(no project)"))
           |> Enum.sort()
           |> Enum.map(fn {p, list} -> {p, Enum.sort_by(list, & &1.name)} end)}
        end)

      {g, by_source}
    end)
  end

  defp group(%{environment: {:env, _} = e}), do: e
  defp group(_), do: :account

  defp group_sort(:account), do: {1, 0, ""}
  defp group_sort(e), do: Environment.sort_key(e)

  defp group_label(:account), do: "Account-wide"
  defp group_label(e), do: Environment.label(e)

  defp env_value(:account), do: "account"
  defp env_value({:env, e}), do: e

  defp visible(results, env, source) do
    for {s, {:ok, stacks}} <- results,
        source in ["all", s.name],
        st <- stacks,
        env == "all" or env_value(group(st)) == env,
        do: st
  end

  defp env_options(results) do
    for({_, {:ok, stacks}} <- results, st <- stacks, do: group(st))
    |> Enum.uniq()
    |> Enum.sort_by(&group_sort/1)
    |> Enum.map(&{group_label(&1), env_value(&1)})
  end

  defp kind_label(:cloudformation), do: "CloudFormation"
  defp kind_label(_), do: "Pulumi"

  defp env_tag({_, v}), do: v

  defp stack_path(s), do: ~p"/sources/#{s.source}/stacks/#{s.project || "_"}/#{s.name}"

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        groups: grouped(visible(assigns.results, assigns.env, assigns.source)),
        env_options: env_options(assigns.results)
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h1 class="text-xl font-semibold">Stacks</h1>
        <form id="filters" phx-change="filter" class="flex gap-2">
          <select name="env" class="select select-sm" aria-label="Environment">
            <option value="all" selected={@env == "all"}>All environments</option>
            <option :for={{label, v} <- @env_options} value={v} selected={@env == v}>{label}</option>
          </select>
          <select name="source" class="select select-sm" aria-label="Source">
            <option value="all" selected={@source == "all"}>All sources</option>
            <option :for={{s, _} <- @results} value={s.name} selected={@source == s.name}>
              {s.name}
            </option>
          </select>
          <button type="button" class="btn btn-sm" phx-click="refresh">
            <.icon name="hero-arrow-path" class="size-4" /> Refresh
          </button>
        </form>
      </div>

      <div
        :for={{s, {:error, msg}} <- @results}
        id={"source-error-#{s.name}"}
        class="alert alert-error flex-col items-start"
      >
        <div class="font-semibold">{s.name} <span class="font-mono text-xs">{s.url}</span></div>
        <div>{msg}</div>
      </div>

      <p
        :for={{s, {:ok, []}} <- @results}
        id={"source-empty-#{s.name}"}
        class="opacity-60"
      >
        No stacks found in <code>{s.name}</code> (<code>{s.url}</code>).
      </p>

      <section :for={{g, by_source} <- @groups} id={"group-#{env_value(g)}"} class="space-y-3">
        <h2 class="text-lg font-semibold">{group_label(g)}</h2>
        <div :for={{src, projects} <- by_source} class="space-y-2 pl-2">
          <div :for={{project, stacks} <- projects} class="space-y-2">
            <h3 class="text-sm uppercase tracking-wide opacity-60">{src} · {project}</h3>
            <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <.link
                :for={s <- stacks}
                navigate={stack_path(s)}
                class="card bg-base-200 hover:bg-base-300 transition p-4"
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="font-semibold truncate">{s.name}</span>
                  <span class="badge badge-sm badge-outline">{env_tag(s.environment)}</span>
                </div>
                <div class="text-sm opacity-70">
                  {s.resource_count} resources
                  <span class={[
                    "badge badge-xs ml-1",
                    if(s.kind == :cloudformation, do: "badge-warning", else: "badge-info")
                  ]}>
                    {kind_label(s.kind)}
                  </span>
                </div>
                <div :if={s.error} class="text-xs text-error">{s.error}</div>
                <div class="text-xs opacity-50">
                  {if s.updated_at,
                    do: Calendar.strftime(s.updated_at, "%Y-%m-%d %H:%M UTC"),
                    else: "never updated"} · {s.pulumi_version}
                </div>
              </.link>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end

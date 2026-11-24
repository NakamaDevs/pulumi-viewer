defmodule PulumiViewerWeb.StacksLive do
  use PulumiViewerWeb, :live_view
  alias PulumiViewer.Environment

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Stacks", q: "", collapsed: MapSet.new())
     |> assign_filter("all", "all")
     |> load()}
  end

  @impl true
  def handle_event("refresh", _, socket), do: {:noreply, load(socket)}

  def handle_event("filter", params, socket),
    do:
      {:noreply,
       socket
       |> assign(q: params["q"] || socket.assigns.q)
       |> assign_filter(
         params["env"] || socket.assigns.env,
         params["source"] || socket.assigns.source
       )}

  def handle_event("toggle_group", %{"group" => g}, socket) do
    collapsed = socket.assigns.collapsed

    collapsed =
      if g in collapsed, do: MapSet.delete(collapsed, g), else: MapSet.put(collapsed, g)

    {:noreply, assign(socket, collapsed: collapsed)}
  end

  defp assign_filter(socket, env, source) do
    assign(socket,
      env: env,
      source: source,
      filter_form: to_form(%{"env" => env, "source" => source, "q" => socket.assigns.q})
    )
  end

  defp load(socket), do: assign(socket, results: PulumiViewerWeb.SourceResults.load())

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

  defp visible(results, env, source, q) do
    q = String.downcase(q || "")

    for {s, {:ok, stacks}} <- results,
        source in ["all", s.name],
        st <- stacks,
        env == "all" or env_value(group(st)) == env,
        q == "" or String.contains?(String.downcase("#{st.name} #{st.project} #{st.source}"), q),
        do: st
  end

  defp env_options(results) do
    for({_, {:ok, stacks}} <- results, st <- stacks, do: group(st))
    |> Enum.uniq()
    |> Enum.sort_by(&group_sort/1)
    |> Enum.map(&{group_label(&1), env_value(&1)})
  end

  defp rows(by_source),
    do: for({src, projects} <- by_source, {p, stacks} <- projects, s <- stacks, do: {src, p, s})

  defp count(by_source),
    do:
      for(
        {_, projects} <- by_source,
        {_, stacks} <- projects,
        reduce: 0,
        do: (n -> n + length(stacks))
      )

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        groups: grouped(visible(assigns.results, assigns.env, assigns.source, assigns.q)),
        env_options: env_options(assigns.results)
      )

    ~H"""
    <Layouts.app flash={@flash} active={:stacks} prefs={@prefs}>
      <.form
        for={@filter_form}
        id="filters"
        phx-change="filter"
        class="flex flex-wrap items-center gap-2 pb-2"
      >
        <div class="relative flex-1 min-w-[220px]">
          <.icon name="hero-magnifying-glass" class="size-4 absolute left-2.5 top-2 opacity-60" />
          <input
            name="q"
            value={@q}
            placeholder="Filter..."
            class="pv-input"
            phx-debounce="150"
            aria-label="Filter"
            autocomplete="off"
          />
        </div>
        <select
          id={@filter_form[:env].id}
          name={@filter_form[:env].name}
          class="pv-select"
          aria-label="Environment"
        >
          <option value="all" selected={@filter_form[:env].value == "all"}>All environments</option>
          <option :for={{label, v} <- @env_options} value={v} selected={@filter_form[:env].value == v}>
            {label}
          </option>
        </select>
        <select
          id={@filter_form[:source].id}
          name={@filter_form[:source].name}
          class="pv-select"
          aria-label="Source"
        >
          <option value="all" selected={@filter_form[:source].value == "all"}>All sources</option>
          <option
            :for={{s, _} <- @results}
            value={s.name}
            selected={@filter_form[:source].value == s.name}
          >
            {s.name}
          </option>
        </select>
        <button
          type="button"
          class="pv-icon-btn border border-base-300 bg-base-100"
          phx-click="refresh"
          title="Refresh"
          aria-label="Refresh"
        >
          <.icon name="hero-arrow-path" class="size-4" />
        </button>
      </.form>

      <div
        :for={{s, {:error, msg}} <- @results}
        id={"source-error-#{s.name}"}
        class="pv-card mb-2 flex items-start gap-3 border-l-4 !border-l-error px-4 py-3"
        role="alert"
      >
        <.icon name="hero-exclamation-circle" class="size-5 text-error shrink-0" />
        <div>
          <div class="font-semibold">
            {s.name} <span class="font-mono text-xs opacity-75">{s.url}</span>
          </div>
          <div>{msg}</div>
        </div>
      </div>

      <p
        :for={{s, {:ok, []}} <- @results}
        id={"source-empty-#{s.name}"}
        class="pv-card mb-2 px-4 py-3 opacity-75"
      >
        No stacks found in <code>{s.name}</code> (<code>{s.url}</code>).
      </p>

      <div class="pv-card overflow-hidden" role="treegrid" aria-label="Stacks">
        <div class="flex items-center gap-2 border-b border-base-300 px-3 py-2">
          <span class="pv-section-title">Stacks</span>
          <span class="pv-count">{@groups |> Enum.map(fn {_, bs} -> count(bs) end) |> Enum.sum()}</span>
        </div>
        <p :if={@groups == []} class="px-4 py-6 text-center opacity-70">
          No stacks match the filter.
        </p>
        <section :for={{g, by_source} <- @groups} id={"group-#{env_value(g)}"}>
          <div
            class="pv-row bg-base-200/60"
            data-group-toggle
            phx-click="toggle_group"
            phx-value-group={env_value(g)}
            role="row"
            aria-expanded={to_string(env_value(g) not in @collapsed)}
          >
            <.icon
              name={
                if env_value(g) in @collapsed,
                  do: "hero-chevron-right-mini",
                  else: "hero-chevron-down-mini"
              }
              class="size-4"
            />
            <.icon
              name={if g == :account, do: "hero-globe-alt", else: "hero-folder"}
              class="size-4 text-primary"
            />
            <h2 class="font-semibold">{group_label(g)}</h2>
            <span class="pv-count">{count(by_source)}</span>
          </div>
          <div
            :for={{src, project, s} <- rows(by_source)}
            :if={env_value(g) not in @collapsed}
            data-row="stack"
          >
            <.link navigate={stack_path(s)} class="pv-row" role="row">
              <span class="pv-indent"></span>
              <.icon name="hero-rectangle-stack" class="size-4 text-primary shrink-0" />
              <span class="font-semibold truncate w-48 max-sm:w-28">{s.name}</span>
              <span class="text-xs opacity-75 truncate w-48 max-md:hidden">{src} · {project}</span>
              <span class="flex items-center gap-1.5 text-xs w-32" title={s.error || "Read"}>
                <.dot state={if s.error, do: "error", else: "ok"} />
                <span class="max-sm:hidden">{if s.error,
                  do: "Error",
                  else: "#{s.resource_count} resources"}</span>
              </span>
              <span class="pv-badge bg-base-200 max-sm:hidden">{env_label(s.environment)}</span>
              <span data-kind={s.kind} class="pv-badge">{kind_label(s.kind)}</span>
              <span class="flex items-center gap-1 text-xs opacity-75 w-40 max-lg:hidden">
                <.icon name="hero-clock" class="size-3.5" /> {time(s.updated_at)}
              </span>
              <span class="text-xs opacity-60 w-14 max-xl:hidden">{s.pulumi_version}</span>
              <span class="flex-1"></span>
              <.icon name="hero-chevron-right" class="size-4 opacity-60" />
            </.link>
            <div :if={s.error} class="px-12 pb-2 text-xs text-error">{s.error}</div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end

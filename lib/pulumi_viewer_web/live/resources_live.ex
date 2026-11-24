defmodule PulumiViewerWeb.ResourcesLive do
  @moduledoc "All resources of all stacks, grouped by stack, like the dashboard Resources page."
  use PulumiViewerWeb, :live_view
  alias PulumiViewer.ResourceTree
  alias PulumiViewerWeb.SourceResults

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Resources",
        q: "",
        package: "all",
        collapsed: MapSet.new(),
        selected: nil,
        results: [],
        stacks: [],
        links: %{},
        loading: true
      )

    {:ok, if(connected?(socket), do: start_async(socket, :load, &load/0), else: socket)}
  end

  defp load do
    results = SourceResults.load()

    stacks =
      results
      |> SourceResults.stacks()
      |> Enum.sort_by(&{env_sort(&1), &1.source, &1.project || "", &1.name})
      |> SourceResults.each_stack(fn st ->
        case PulumiViewer.Infra.list_resources(st.project, st.name, st.source) do
          {:ok, rs} -> {:ok, rs}
          {:error, e} -> {:error, PulumiViewer.error_message(e)}
        end
      end)

    links =
      if length(PulumiViewer.Sources.all()) > 1,
        do: Map.new([:pulumi, :cloudformation], &{&1, PulumiViewer.Infra.Links.index(&1)}),
        else: %{}

    %{results: results, stacks: stacks, links: links}
  end

  defp env_sort(%{environment: {:env, _} = e}), do: PulumiViewer.Environment.sort_key(e)
  defp env_sort(_), do: {1, 0, ""}

  @impl true
  def handle_async(:load, {:ok, data}, socket),
    do: {:noreply, socket |> assign(data) |> assign(loading: false)}

  def handle_async(:load, {:exit, reason}, socket),
    do:
      {:noreply,
       socket
       |> assign(loading: false)
       |> put_flash(:error, "Read failed: #{inspect(reason)}")}

  @impl true
  def handle_event("filter", params, socket),
    do:
      {:noreply,
       assign(socket,
         q: params["q"] || socket.assigns.q,
         package: params["package"] || socket.assigns.package
       )}

  def handle_event("toggle", params, socket) do
    k = toggle_key(params)
    c = socket.assigns.collapsed

    {:noreply,
     assign(socket, collapsed: if(k in c, do: MapSet.delete(c, k), else: MapSet.put(c, k)))}
  end

  def handle_event("select", %{"key" => key, "urn" => urn}, socket),
    do: {:noreply, assign(socket, selected: {key, urn})}

  # a dependency link in the details panel: same stack as the open resource
  def handle_event("select", %{"urn" => urn}, socket) do
    case socket.assigns.selected do
      {key, _} -> {:noreply, assign(socket, selected: {key, urn})}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close", _, socket), do: {:noreply, assign(socket, selected: nil)}

  def handle_event("refresh", _, socket),
    do: {:noreply, socket |> assign(loading: true) |> start_async(:load, &load/0)}

  defp toggle_key(%{"key" => k, "urn" => u}), do: k <> "|" <> u
  defp toggle_key(%{"key" => k}), do: k

  defp rows(resources, key, collapsed, q, package) do
    stack_collapsed =
      for c <- collapsed,
          String.starts_with?(c, key <> "|"),
          into: MapSet.new(),
          do: String.replace_prefix(c, key <> "|", "")

    resources
    |> Enum.filter(&(package == "all" or &1.package == package))
    |> ResourceTree.flatten(stack_collapsed)
    |> ResourceTree.filter(q)
  end

  defp packages(stacks),
    do:
      for({_, {:ok, rs}} <- stacks, r <- rs, r.package, uniq: true, do: r.package) |> Enum.sort()

  defp selected(stacks, {key, urn}) do
    Enum.find_value(stacks, fn
      {st, {:ok, rs}} ->
        if SourceResults.key(st) == key, do: {st, rs, Enum.find(rs, &(&1.urn == urn))}

      _ ->
        nil
    end)
  end

  defp selected(_, _), do: nil

  defp links_for(links, st, r),
    do: links |> Map.get(st.kind || :pulumi, %{}) |> Map.get(r.id || "", [])

  @impl true
  def render(assigns) do
    shown =
      for {st, res} <- assigns.stacks do
        key = SourceResults.key(st)

        case res do
          {:ok, rs} ->
            {st, key, {:ok, rows(rs, key, assigns.collapsed, assigns.q, assigns.package)}}

          err ->
            {st, key, err}
        end
      end
      |> Enum.reject(fn {_, _, r} -> assigns.q != "" and r == {:ok, []} end)

    assigns =
      assign(assigns,
        shown: shown,
        sel: selected(assigns.stacks, assigns.selected),
        total: Enum.sum(for({_, _, {:ok, rows}} <- shown, do: length(rows)))
      )

    ~H"""
    <Layouts.app flash={@flash} active={:resources} prefs={@prefs} full>
      <.split orientation={@prefs.orientation} open={match?({_, _, %{}}, @sel)}>
        <:master>
          <div class="flex h-full flex-col">
            <form
              id="resource-filter"
              phx-change="filter"
              phx-submit="filter"
              class="flex flex-wrap items-center gap-2 border-b border-base-300 p-2"
            >
              <div class="relative flex-1 min-w-[200px]">
                <.icon name="hero-magnifying-glass" class="size-4 absolute left-2.5 top-2 opacity-60" />
                <input
                  name="q"
                  value={@q}
                  placeholder="Filter by name, type or id"
                  class="pv-input"
                  phx-debounce="150"
                  aria-label="Filter"
                  autocomplete="off"
                />
              </div>
              <select name="package" class="pv-select" aria-label="Provider">
                <option value="all" selected={@package == "all"}>All providers</option>
                <option :for={p <- packages(@stacks)} value={p} selected={@package == p}>{p}</option>
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
            </form>
            <div class="flex items-center gap-2 border-b border-base-300 px-3 py-2">
              <span class="pv-section-title">Resources</span>
              <span class="pv-count">{@total}</span>
              <span :if={@loading} class="loading loading-spinner loading-xs"></span>
            </div>
            <div
              :for={{s, {:error, msg}} <- @results}
              id={"source-error-#{s.name}"}
              class="flex items-start gap-2 border-b border-base-300 px-3 py-2 text-error"
              role="alert"
            >
              <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
              <span><b>{s.name}</b>: {msg}</span>
            </div>
            <div
              id="resource-list"
              role="treegrid"
              aria-label="Resources"
              class="flex-1 overflow-auto"
            >
              <div :for={{st, key, res} <- @shown} data-stack-group={key}>
                <div
                  class="pv-row bg-base-200/60"
                  phx-click="toggle"
                  phx-value-key={key}
                  role="row"
                  aria-expanded={to_string(key not in @collapsed)}
                >
                  <.icon
                    name={
                      if key in @collapsed,
                        do: "hero-chevron-right-mini",
                        else: "hero-chevron-down-mini"
                    }
                    class="size-4"
                  />
                  <.icon name="hero-rectangle-stack" class="size-4 text-primary" />
                  <span class="font-semibold">{st.name}</span>
                  <span class="text-xs opacity-75 max-sm:hidden">{st.source} · {st.project ||
                    "(no project)"}</span>
                  <span class="pv-badge bg-base-100">{env_label(st.environment)}</span>
                  <.source_badge kind={st.kind || :pulumi} />
                  <span class="flex-1"></span>
                  <span :if={match?({:ok, _}, res)} class="pv-count">{elem(res, 1) |> length()}</span>
                </div>
                <div :if={key not in @collapsed}>
                  <%= case res do %>
                    <% {:ok, rows} -> %>
                      <.resource_rows
                        rows={rows}
                        key={key}
                        base_depth={1}
                        selected={match?({^key, _}, @selected) && elem(@selected, 1)}
                      />
                    <% {:error, msg} -> %>
                      <div class="px-10 py-2 text-xs text-error">{msg}</div>
                  <% end %>
                </div>
              </div>
              <p :if={!@loading and @shown == []} class="px-4 py-6 text-center opacity-70">
                No resources.
              </p>
            </div>
          </div>
        </:master>
        <:details>
          <%= case @sel do %>
            <% {st, rs, %{} = r} -> %>
              <.resource_details r={r} resources={rs} stack={st} links={links_for(@links, st, r)} />
            <% _ -> %>
          <% end %>
        </:details>
      </.split>
    </Layouts.app>
    """
  end
end

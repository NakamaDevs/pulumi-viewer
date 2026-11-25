defmodule PulumiViewerWeb.StackLive do
  use PulumiViewerWeb, :live_view
  alias PulumiViewer.Infra
  alias PulumiViewer.Pulumi.Graph

  @impl true
  def mount(%{"project" => project, "stack" => stack} = params, _session, socket) do
    project = if project == "_", do: nil, else: project

    case PulumiViewer.Sources.fetch(params["source"]) do
      {:ok, src} ->
        socket =
          socket
          |> assign(project: project, stack: stack, source: src)
          |> assign(page_title: "#{src.name}/#{project}/#{stack}")
          |> assign(tab: start_tab(socket), q: "", selected: nil, providers: false, updates: nil)
          |> assign(collapsed: MapSet.new(), selected_update: nil)
          |> assign_links(src)
          |> assign_checks(src, project, stack)

        case Infra.list_resources(project, stack, src.name) do
          {:ok, resources} ->
            {:ok, socket |> assign(resources: resources, missing: false) |> graph()}

          {:error, e} ->
            {:ok, assign(socket, resources: [], missing: problem(e), graph_json: "{}")}
        end

      _ ->
        {:ok,
         assign(socket,
           project: project,
           stack: stack,
           source: %{name: params["source"], kind: nil},
           page_title: stack,
           tab: "resources",
           collapsed: MapSet.new(),
           selected_update: nil,
           resources: [],
           selected: nil,
           providers: false,
           updates: nil,
           q: "",
           links: %{},
           checks: %{},
           graph_json: "{}",
           missing: "Unknown source #{params["source"]}."
         )}
    end
  end

  # Same physical ID in a source of the other kind; loaded after the page renders.
  defp assign_links(socket, src) do
    if connected?(socket) and length(PulumiViewer.Sources.all()) > 1 do
      socket
      |> assign(links: %{})
      |> start_async(:links, fn -> PulumiViewer.Infra.Links.index(src.kind) end)
    else
      assign(socket, links: %{})
    end
  end

  # Flags, owner and findings of each resource (PulumiViewer.Checks); Pulumi stacks only.
  defp assign_checks(socket, %{kind: :pulumi} = src, project, stack) do
    socket = assign(socket, checks: %{})

    if connected?(socket) do
      start_async(socket, :checks, fn ->
        case PulumiViewer.Checks.for_stack(src.name, project, stack) do
          {:ok, %{resources: rs, findings: fs}} ->
            fs = Enum.group_by(fs, & &1.urn)
            Map.new(rs, &{&1.urn, %{owner: &1.owner, findings: Map.get(fs, &1.urn, [])}})

          _ ->
            %{}
        end
      end)
    else
      socket
    end
  end

  defp assign_checks(socket, _, _, _), do: assign(socket, checks: %{})

  @impl true
  def handle_async(:checks, {:ok, checks}, socket), do: {:noreply, assign(socket, checks: checks)}
  def handle_async(:checks, _, socket), do: {:noreply, socket}

  def handle_async(:links, {:ok, links}, socket), do: {:noreply, assign(socket, links: links)}
  def handle_async(:links, _, socket), do: {:noreply, socket}

  @impl true
  def handle_event("tab", %{"tab" => "history"}, socket) do
    updates =
      socket.assigns.updates ||
        Infra.list_updates!(
          socket.assigns.project,
          socket.assigns.stack,
          socket.assigns.source.name
        )

    {:noreply, assign(socket, tab: "history", updates: updates)}
  end

  def handle_event("tab", %{"tab" => "list"}, socket),
    do: {:noreply, assign(socket, tab: start_tab(socket))}

  def handle_event("tab", %{"tab" => tab}, socket) when tab in ["graph", "resources"],
    do: {:noreply, assign(socket, tab: tab)}

  def handle_event("filter", %{"q" => q}, socket), do: {:noreply, assign(socket, q: q)}

  def handle_event("close", _, socket),
    do: {:noreply, assign(socket, selected: nil, selected_update: nil)}

  def handle_event("toggle", %{"urn" => urn}, socket) do
    c = socket.assigns.collapsed

    {:noreply,
     assign(socket, collapsed: if(urn in c, do: MapSet.delete(c, urn), else: MapSet.put(c, urn)))}
  end

  def handle_event("select_update", %{"version" => v}, socket) do
    u = Enum.find(socket.assigns.updates || [], &(to_string(&1.version) == v))
    {:noreply, assign(socket, selected_update: u, selected: nil)}
  end

  def handle_event("providers", _, socket),
    do: {:noreply, socket |> update(:providers, &(!&1)) |> graph()}

  def handle_event("select", %{"urn" => urn}, socket) do
    {:noreply,
     assign(socket,
       selected: Enum.find(socket.assigns.resources, &(&1.urn == urn)),
       selected_update: nil
     )}
  end

  defp start_tab(socket),
    do: if(socket.assigns.prefs.view == "graph", do: "graph", else: "resources")

  @doc false
  # the view option changed in the settings: follow it unless History is open.
  # Other options (density, orientation) leave the open view as it is.
  def prefs_changed(socket, %{view: same}, %{view: same}), do: socket

  def prefs_changed(socket, _old, prefs) do
    if socket.assigns[:tab] in ["graph", "resources"],
      do: assign(socket, tab: if(prefs.view == "graph", do: "graph", else: "resources")),
      else: socket
  end

  # a source error (for example expired AWS credentials) is more useful than "not found"
  defp problem(e) do
    msg = PulumiViewer.error_message(e)
    if msg =~ "not_found", do: "Stack not found.", else: msg
  end

  defp graph(socket) do
    g = Graph.build(socket.assigns.resources, providers: socket.assigns.providers)
    assign(socket, graph_json: Jason.encode!(g))
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        rows:
          assigns.resources
          |> PulumiViewer.ResourceTree.flatten(
            if(assigns.q == "", do: assigns.collapsed, else: MapSet.new())
          )
          |> PulumiViewer.ResourceTree.filter(assigns.q)
      )

    ~H"""
    <Layouts.app flash={@flash} active={:stacks} prefs={@prefs} full>
      <div class="flex flex-wrap items-center gap-2 pb-2">
        <nav class="breadcrumbs py-0 text-sm" aria-label="Breadcrumb">
          <ul>
            <li><.link navigate={~p"/"}>Stacks</.link></li>
            <li>{@source.name}</li>
            <li>{@project || "(no project)"}</li>
            <li class="font-semibold">{@stack}</li>
          </ul>
        </nav>
        <.source_badge :if={@source.kind} kind={@source.kind} />
        <span class="flex-1"></span>
        <div :if={!@missing} class="pv-seg" role="tablist" aria-label="Page">
          <button
            :for={
              {t, label} <- [
                {"resources", "Resources (#{length(@resources)})"},
                {"history", "History"}
              ]
            }
            type="button"
            role="tab"
            phx-click="tab"
            phx-value-tab={if t == "resources", do: "list", else: t}
            aria-pressed={to_string(@tab == t or (t == "resources" and @tab == "graph"))}
          >
            {label}
          </button>
        </div>
      </div>

      <div
        :if={@missing}
        id="stack-missing"
        class="pv-card flex items-center gap-3 border-l-4 !border-l-warning px-4 py-3"
        role="alert"
      >
        <.icon name="hero-exclamation-triangle" class="size-5 text-warning" /> {@missing}
      </div>

      <.split
        :if={!@missing}
        orientation={@prefs.orientation}
        open={!!(@selected || @selected_update)}
      >
        <:master>
          <div :if={@tab != "history"} class="flex h-full flex-col">
            <div class="flex flex-wrap items-center gap-2 border-b border-base-300 p-2">
              <form
                :if={@tab == "resources"}
                id="filter"
                phx-change="filter"
                phx-submit="filter"
                class="relative flex-1 min-w-[200px]"
              >
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
              </form>
              <span :if={@tab == "graph"} class="flex-1"></span>
              <label :if={@tab == "graph"} class="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  class="toggle toggle-sm toggle-primary"
                  checked={@providers}
                  phx-click="providers"
                /> Show providers
              </label>
              <.view_toggle tab={@tab} />
            </div>
            <%!-- ignore keeps React DOM; LiveView still patches data-graph and calls updated() --%>
            <div
              :if={@tab == "graph"}
              id="graph"
              phx-hook="ResourceGraph"
              phx-update="ignore"
              data-graph={@graph_json}
              class="min-h-[60vh] flex-1"
            >
            </div>
            <div
              :if={@tab == "resources"}
              id="resource-list"
              role="treegrid"
              aria-label="Resources"
              class="flex-1 overflow-auto"
            >
              <.resource_rows rows={@rows} selected={@selected && @selected.urn} checks={@checks} />
              <p :if={@rows == []} class="px-4 py-6 text-center opacity-70">
                No resources match the filter.
              </p>
            </div>
          </div>

          <table :if={@tab == "history"} id="history" class="table table-sm">
            <thead>
              <tr>
                <th>#</th><th>Time (UTC)</th><th>Kind</th><th>Result</th><th>Duration</th><th>
                  Changes
                </th><th>Message</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={u <- @updates || []}
                data-update={u.version}
                class={[
                  "cursor-pointer hover:bg-base-200",
                  @selected_update && @selected_update.version == u.version && "bg-base-200"
                ]}
                phx-click="select_update"
                phx-value-version={u.version}
              >
                <td>{version_label(u)}</td>
                <td class="text-xs whitespace-nowrap">
                  {u.started_at && Calendar.strftime(u.started_at, "%Y-%m-%d %H:%M")}
                </td>
                <td>{u.kind}</td>
                <td><span class="pv-chip" data-result={u.result}>{u.result}</span></td>
                <td class="text-xs">{duration(u.duration_s)}</td>
                <td class="text-xs font-mono">{changes(u.changes)}</td>
                <td class="text-xs">{u.message}</td>
              </tr>
            </tbody>
          </table>
        </:master>
        <:details>
          <.resource_details
            :if={@selected}
            r={@selected}
            links={Map.get(@links, @selected.id || "", [])}
            resources={@resources}
            check={@checks[@selected.urn]}
          />
          <.update_details :if={@selected_update} u={@selected_update} />
        </:details>
      </.split>
    </Layouts.app>
    """
  end
end

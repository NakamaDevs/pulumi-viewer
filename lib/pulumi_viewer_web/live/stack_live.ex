defmodule PulumiViewerWeb.StackLive do
  use PulumiViewerWeb, :live_view
  alias PulumiViewer.Infra
  alias PulumiViewer.Pulumi.Graph

  @impl true
  def mount(%{"project" => project, "stack" => stack}, _session, socket) do
    project = if project == "_", do: nil, else: project

    socket =
      socket
      |> assign(project: project, stack: stack, page_title: "#{project}/#{stack}")
      |> assign(tab: "graph", q: "", selected: nil, providers: false, updates: nil)

    case Infra.list_resources(project, stack) do
      {:ok, resources} -> {:ok, socket |> assign(resources: resources, missing: false) |> graph()}
      {:error, _} -> {:ok, assign(socket, resources: [], missing: true, graph_json: "{}")}
    end
  end

  @impl true
  def handle_event("tab", %{"tab" => "history"}, socket) do
    updates =
      socket.assigns.updates || Infra.list_updates!(socket.assigns.project, socket.assigns.stack)

    {:noreply, assign(socket, tab: "history", updates: updates)}
  end

  def handle_event("tab", %{"tab" => tab}, socket), do: {:noreply, assign(socket, tab: tab)}
  def handle_event("filter", %{"q" => q}, socket), do: {:noreply, assign(socket, q: q)}
  def handle_event("close", _, socket), do: {:noreply, assign(socket, selected: nil)}

  def handle_event("providers", _, socket),
    do: {:noreply, socket |> update(:providers, &(!&1)) |> graph()}

  def handle_event("select", %{"urn" => urn}, socket) do
    {:noreply, assign(socket, selected: Enum.find(socket.assigns.resources, &(&1.urn == urn)))}
  end

  defp graph(socket) do
    g = Graph.build(socket.assigns.resources, providers: socket.assigns.providers)
    assign(socket, graph_json: Jason.encode!(g))
  end

  defp filtered(resources, ""), do: resources

  defp filtered(resources, q) do
    q = String.downcase(q)

    Enum.filter(
      resources,
      &String.contains?(String.downcase("#{&1.name} #{&1.type} #{&1.id}"), q)
    )
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :code, :string, required: true

  # Rendered in the browser by @pierre/diffs (the diffs.com code viewer). The <pre> is the
  # no-JS fallback and is replaced on mount.
  defp code_block(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="CodeBlock"
      phx-update="ignore"
      data-name={@name}
      data-code={@code}
      class="rounded overflow-hidden text-xs"
    >
      <pre class="bg-base-100 p-2 overflow-auto">{@code}</pre>
    </div>
    """
  end

  defp pretty(term), do: Jason.encode!(term, pretty: true)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="breadcrumbs text-sm">
        <ul>
          <li><.link navigate={~p"/"}>Stacks</.link></li>
          <li>{@project || "(no project)"}</li>
          <li class="font-semibold">{@stack}</li>
        </ul>
      </div>

      <div :if={@missing} class="alert alert-warning">Stack not found.</div>

      <div :if={!@missing} class="space-y-4">
        <div class="flex items-center gap-2">
          <div role="tablist" class="tabs tabs-box">
            <button
              :for={
                {t, label} <- [
                  {"graph", "Graph"},
                  {"resources", "Resources (#{length(@resources)})"},
                  {"history", "History"}
                ]
              }
              role="tab"
              class={["tab", @tab == t && "tab-active"]}
              phx-click="tab"
              phx-value-tab={t}
            >
              {label}
            </button>
          </div>
          <label :if={@tab == "graph"} class="label text-sm ml-auto">
            <input
              type="checkbox"
              class="toggle toggle-sm"
              checked={@providers}
              phx-click="providers"
            /> Show providers
          </label>
        </div>

        <div class="flex gap-4">
          <div class="flex-1 min-w-0">
            <%!-- ignore keeps React DOM; LiveView still patches data-graph and calls updated() --%>
            <div
              :if={@tab == "graph"}
              id="graph"
              phx-hook="ResourceGraph"
              phx-update="ignore"
              data-graph={@graph_json}
              class="h-[75vh] rounded-box border border-base-300"
            >
            </div>

            <div :if={@tab == "resources"} class="space-y-2">
              <form id="filter" phx-change="filter" phx-submit="filter">
                <input
                  name="q"
                  value={@q}
                  placeholder="Filter by name, type or id"
                  class="input input-sm w-full max-w-md"
                  phx-debounce="150"
                />
              </form>
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Name</th><th>Type</th><th>Physical ID</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={r <- filtered(@resources, @q)}
                    class="hover cursor-pointer"
                    phx-click="select"
                    phx-value-urn={r.urn}
                  >
                    <td class="font-medium">{if r.protect, do: "🔒 "}{r.name}</td>
                    <td class="font-mono text-xs">{r.type}</td>
                    <td class="font-mono text-xs truncate max-w-xs">{r.id}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <table :if={@tab == "history"} class="table table-sm">
              <thead>
                <tr>
                  <th>#</th><th>When (UTC)</th><th>Kind</th><th>Result</th><th>Changes</th><th>
                    Message
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={u <- @updates || []}>
                  <td>{u.version}</td>
                  <td class="text-xs">
                    {u.started_at && Calendar.strftime(u.started_at, "%Y-%m-%d %H:%M")}
                  </td>
                  <td>{u.kind}</td>
                  <td>
                    <span class={[
                      "badge badge-sm",
                      u.result == "succeeded" && "badge-success",
                      u.result == "failed" && "badge-error"
                    ]}>
                      {u.result}
                    </span>
                  </td>
                  <td class="text-xs">
                    {Enum.map_join(u.changes || %{}, " ", fn {k, v} -> "#{k}:#{v}" end)}
                  </td>
                  <td class="text-xs">{u.message}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <aside
            :if={@selected}
            class="w-[420px] shrink-0 card bg-base-200 p-4 space-y-3 max-h-[75vh] overflow-auto"
          >
            <div class="flex items-start justify-between gap-2">
              <div>
                <div class="font-semibold">{@selected.name}</div>
                <div class="font-mono text-xs opacity-70">{@selected.type}</div>
              </div>
              <button class="btn btn-ghost btn-xs" phx-click="close">
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
            <dl class="text-xs space-y-1">
              <div>
                <dt class="opacity-60">URN</dt>
                <dd class="font-mono break-all">{@selected.urn}</dd>
              </div>
              <div :if={@selected.id}>
                <dt class="opacity-60">Physical ID</dt>
                <dd class="font-mono break-all">{@selected.id}</dd>
              </div>
              <div :if={@selected.parent_urn}>
                <dt class="opacity-60">Parent</dt>
                <dd class="font-mono break-all">{@selected.parent_urn}</dd>
              </div>
            </dl>
            <details open>
              <summary class="text-sm font-semibold cursor-pointer">Outputs</summary>
              <.code_block
                id={"out-#{@selected.urn}"}
                name="outputs.json"
                code={pretty(@selected.outputs)}
              />
            </details>
            <details>
              <summary class="text-sm font-semibold cursor-pointer">Inputs</summary>
              <.code_block
                id={"in-#{@selected.urn}"}
                name="inputs.json"
                code={pretty(@selected.inputs)}
              />
            </details>
            <details>
              <summary class="text-sm font-semibold cursor-pointer">Raw resource</summary>
              <.code_block
                id={"raw-#{@selected.urn}"}
                name="resource.json"
                code={
                  pretty(
                    Map.from_struct(@selected)
                    |> Map.drop([
                      :__meta__,
                      :__metadata__,
                      :__lateral_join_source__,
                      :aggregates,
                      :calculations
                    ])
                  )
                }
              />
            </details>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

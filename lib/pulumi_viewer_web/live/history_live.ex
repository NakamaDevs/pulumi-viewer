defmodule PulumiViewerWeb.HistoryLive do
  @moduledoc "Updates of all stacks, newest first, like the dashboard Structured logs list."
  use PulumiViewerWeb, :live_view
  alias PulumiViewerWeb.SourceResults

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "History",
        q: "",
        result: "all",
        updates: [],
        results: [],
        failed: [],
        selected: nil,
        loading: true
      )

    {:ok, if(connected?(socket), do: start_async(socket, :load, &load/0), else: socket)}
  end

  defp load do
    results = SourceResults.load()
    per_stack = SourceResults.each_stack(SourceResults.stacks(results), &stack_updates/1)

    updates =
      for(
        {st, {:ok, us}} <- per_stack,
        u <- us,
        do: %{id: "#{SourceResults.key(st)}##{u.version}", stack: st, u: u}
      )
      |> Enum.sort_by(&sort_time(&1.u.started_at), :desc)

    %{
      results: results,
      updates: updates,
      failed: for({st, {:error, m}} <- per_stack, do: {st, m})
    }
  end

  defp stack_updates(st) do
    case PulumiViewer.Infra.list_updates(st.project, st.name, st.source) do
      {:ok, us} -> {:ok, us}
      {:error, e} -> {:error, PulumiViewer.error_message(e)}
    end
  end

  defp sort_time(nil), do: 0
  defp sort_time(%DateTime{} = t), do: DateTime.to_unix(t)
  defp sort_time(_), do: 0

  @impl true
  def handle_async(:load, {:ok, data}, socket),
    do: {:noreply, socket |> assign(data) |> assign(loading: false)}

  def handle_async(:load, {:exit, reason}, socket),
    do:
      {:noreply,
       socket |> assign(loading: false) |> put_flash(:error, "Read failed: #{inspect(reason)}")}

  @impl true
  def handle_event("filter", params, socket),
    do:
      {:noreply,
       assign(socket,
         q: params["q"] || socket.assigns.q,
         result: params["result"] || socket.assigns.result
       )}

  # keep the id, not the entry: after a refresh the panel shows the reloaded update
  def handle_event("select_update", %{"id" => id}, socket),
    do: {:noreply, assign(socket, selected: id)}

  def handle_event("close", _, socket), do: {:noreply, assign(socket, selected: nil)}

  def handle_event("refresh", _, socket),
    do: {:noreply, socket |> assign(loading: true) |> start_async(:load, &load/0)}

  defp visible(updates, q, result) do
    q = String.downcase(q)

    Enum.filter(updates, fn %{stack: st, u: u} ->
      (result == "all" or u.result == result) and
        (q == "" or
           String.contains?(String.downcase("#{st.name} #{st.source} #{u.kind} #{u.message}"), q))
    end)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        shown: visible(assigns.updates, assigns.q, assigns.result),
        sel: assigns.selected && Enum.find(assigns.updates, &(&1.id == assigns.selected))
      )

    ~H"""
    <Layouts.app flash={@flash} active={:history} prefs={@prefs} full>
      <.split orientation={@prefs.orientation} open={@sel != nil}>
        <:master>
          <div class="flex h-full flex-col">
            <form
              id="history-filter"
              phx-change="filter"
              phx-submit="filter"
              class="flex flex-wrap items-center gap-2 border-b border-base-300 p-2"
            >
              <div class="relative flex-1 min-w-[200px]">
                <.icon name="hero-magnifying-glass" class="size-4 absolute left-2.5 top-2 opacity-60" />
                <input
                  name="q"
                  value={@q}
                  placeholder="Filter by stack, kind or message"
                  class="pv-input"
                  phx-debounce="150"
                  aria-label="Filter"
                  autocomplete="off"
                />
              </div>
              <select name="result" class="pv-select" aria-label="Result">
                <option
                  :for={
                    {v, l} <- [
                      {"all", "All results"},
                      {"succeeded", "Succeeded"},
                      {"failed", "Failed"},
                      {"in-progress", "In progress"}
                    ]
                  }
                  value={v}
                  selected={@result == v}
                >
                  {l}
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
            </form>
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
              :for={{st, msg} <- @failed}
              class="border-b border-base-300 px-3 py-2 text-xs text-error"
            >
              {st.name} ({st.source}): {msg}
            </div>
            <div class="flex-1 overflow-auto">
              <table id="history" class="table table-sm">
                <thead class="sticky top-0 bg-base-100">
                  <tr>
                    <th>Time (UTC)</th><th>Stack</th><th>Kind</th><th>Result</th><th>Duration</th><th class="max-md:hidden">
                      Changes
                    </th><th class="max-lg:hidden">Message</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={e <- @shown}
                    data-update={e.id}
                    data-result={e.u.result}
                    class={[
                      "cursor-pointer hover:bg-base-200",
                      @selected == e.id && "bg-base-200"
                    ]}
                    phx-click="select_update"
                    phx-value-id={e.id}
                  >
                    <td class="text-xs whitespace-nowrap">
                      {e.u.started_at && Calendar.strftime(e.u.started_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td>
                      <span class="font-semibold">{e.stack.name}</span>
                      <span class="text-xs opacity-60">{env_label(e.stack.environment)}</span>
                    </td>
                    <td>{e.u.kind}</td>
                    <td><span class="pv-chip" data-result={e.u.result}>{e.u.result}</span></td>
                    <td class="text-xs">{duration(e.u.duration_s)}</td>
                    <td class="text-xs font-mono max-md:hidden">{changes(e.u.changes)}</td>
                    <td class="text-xs max-lg:hidden truncate max-w-[24rem]">{e.u.message}</td>
                  </tr>
                </tbody>
              </table>
              <p :if={@loading} class="px-4 py-6 text-center opacity-70">Reading the history...</p>
              <p :if={!@loading and @shown == []} class="px-4 py-6 text-center opacity-70">
                No updates.
              </p>
            </div>
          </div>
        </:master>
        <:details>
          <.update_details :if={@sel} u={@sel.u} stack={@sel.stack} />
        </:details>
      </.split>
    </Layouts.app>
    """
  end
end

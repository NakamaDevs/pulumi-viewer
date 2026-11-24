defmodule PulumiViewerWeb.StacksLive do
  use PulumiViewerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Stacks") |> load()}
  end

  @impl true
  def handle_event("refresh", _, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    case PulumiViewer.Infra.list_stacks() do
      {:ok, stacks} ->
        assign(socket, stacks: Enum.group_by(stacks, &(&1.project || "(no project)")), error: nil)

      {:error, e} ->
        assign(socket, stacks: %{}, error: PulumiViewer.error_message(e))
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-semibold">Stacks</h1>
        <button class="btn btn-sm" phx-click="refresh">
          <.icon name="hero-arrow-path" class="size-4" /> Refresh
        </button>
      </div>

      <div :if={@error} class="alert alert-error">{@error}</div>
      <p :if={!@error and @stacks == %{}} class="opacity-60">
        No stacks found in <code>{PulumiViewer.backend_label()}</code>.
      </p>

      <section :for={{project, stacks} <- Enum.sort(@stacks)} class="space-y-2">
        <h2 class="text-sm uppercase tracking-wide opacity-60">{project}</h2>
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <.link
            :for={s <- Enum.sort_by(stacks, & &1.name)}
            navigate={~p"/stacks/#{s.project || "_"}/#{s.name}"}
            class="card bg-base-200 hover:bg-base-300 transition p-4"
          >
            <div class="font-semibold">{s.name}</div>
            <div class="text-sm opacity-70">{s.resource_count} resources</div>
            <div class="text-xs opacity-50">
              {if s.updated_at,
                do: Calendar.strftime(s.updated_at, "%Y-%m-%d %H:%M UTC"),
                else: "never updated"} · {s.pulumi_version}
            </div>
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end
end

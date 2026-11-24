defmodule PulumiViewerWeb.StacksLive do
  use PulumiViewerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Stacks") |> load()}
  end

  @impl true
  def handle_event("refresh", _, socket), do: {:noreply, load(socket)}

  # Every source loads at the same time; one that fails shows its own error.
  defp load(socket) do
    sources = PulumiViewer.Storage.sources()

    sources =
      sources
      |> Task.async_stream(&load_source/1,
        timeout: 120_000,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.zip(sources)
      |> Enum.map(fn
        {{:ok, s}, _src} -> s
        {{:exit, _}, src} -> failed(src, "#{src.name} did not answer within 120 s.")
      end)

    assign(socket, sources: sources, multiple?: length(sources) > 1)
  end

  # a bad URL or a duplicate name: show the config error, do not read another source by name
  defp load_source(%{error: why} = src) when is_binary(why), do: failed(src, why)

  defp load_source(src) do
    case PulumiViewer.Infra.list_stacks(src.name) do
      {:ok, stacks} ->
        %{
          name: src.name,
          url: src.url,
          error: nil,
          stacks: Enum.group_by(stacks, &(&1.project || "(no project)"))
        }

      {:error, e} ->
        failed(src, PulumiViewer.error_message(e))
    end
  rescue
    # a source that raises (for example S3 without access) must not take down the page
    e -> failed(src, PulumiViewer.error_message(e))
  end

  defp failed(src, message), do: %{name: src.name, url: src.url, error: message, stacks: %{}}

  # keep single-source links short: /stacks/demo/dev
  defp source_query(true, source), do: [source: source]
  defp source_query(false, _source), do: []

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

      <div :for={src <- @sources} class="space-y-4">
        <h2 :if={@multiple?} class="text-lg font-semibold flex items-baseline gap-2 pt-2">
          {src.name} <code class="text-xs font-normal opacity-60">{src.url}</code>
        </h2>
        <div :if={src.error} class="alert alert-error">
          <span :if={@multiple?} class="font-semibold">{src.name}:</span> {src.error}
        </div>
        <p :if={!src.error and src.stacks == %{}} class="opacity-60">
          No stacks found in <code>{src.url}</code>.
        </p>

        <section :for={{project, stacks} <- Enum.sort(src.stacks)} class="space-y-2">
          <h3 class="text-sm uppercase tracking-wide opacity-60">{project}</h3>
          <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <.link
              :for={s <- Enum.sort_by(stacks, & &1.name)}
              navigate={
                ~p"/stacks/#{s.project || "_"}/#{s.name}?#{source_query(@multiple?, s.source)}"
              }
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
      </div>
    </Layouts.app>
    """
  end
end

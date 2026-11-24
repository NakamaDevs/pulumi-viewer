defmodule PulumiViewerWeb.Dashboard do
  @moduledoc """
  Building blocks with the layout of the Aspire 17 dashboard: toolbar with a filter box,
  tree rows, state dots and chips, the master/detail split and key-value cards.
  """
  use Phoenix.Component
  use PulumiViewerWeb, :verified_routes
  import PulumiViewerWeb.CoreComponents
  alias Phoenix.LiveView.JS

  def kind_label(:cloudformation), do: "CloudFormation"
  def kind_label(_), do: "Pulumi"

  def stack_path(%{source: src, project: p, name: n}),
    do: ~p"/sources/#{src}/stacks/#{p || "_"}/#{n}"

  def env_label({:env, e}), do: e
  def env_label(_), do: "Account-wide"

  def time(nil), do: "never"
  def time(%DateTime{} = t), do: Calendar.strftime(t, "%Y-%m-%d %H:%M UTC")
  def time(%NaiveDateTime{} = t), do: Calendar.strftime(t, "%Y-%m-%d %H:%M")
  def time(t), do: to_string(t)

  def duration(nil), do: ""
  def duration(s) when s < 60, do: "#{s}s"
  def duration(s), do: "#{div(s, 60)}m #{rem(s, 60)}s"

  def changes(nil), do: ""
  def changes(c), do: c |> Enum.sort() |> Enum.map_join(" ", fn {k, v} -> "#{k}:#{v}" end)

  @doc "Icon for a provider package."
  def provider_icon("aws"), do: "hero-cloud"
  def provider_icon("pulumi"), do: "hero-cube-transparent"
  def provider_icon("kubernetes"), do: "hero-server-stack"
  def provider_icon("random"), do: "hero-sparkles"
  def provider_icon("command"), do: "hero-command-line"
  def provider_icon(_), do: "hero-cube"

  attr :kind, :atom, required: true

  def source_badge(assigns) do
    ~H"""
    <span class="pv-badge" data-kind={@kind}>{kind_label(@kind)}</span>
    """
  end

  attr :state, :string, required: true
  attr :title, :string, default: nil

  def dot(assigns) do
    ~H"""
    <span class="pv-dot" data-state={@state} title={@title}></span>
    """
  end

  attr :id, :string, required: true
  attr :q, :string, default: ""
  attr :placeholder, :string, default: "Filter..."
  slot :inner_block

  @doc "The dashboard toolbar: a full-width filter box, then extra controls."
  def toolbar(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 pb-2">
      <form id={@id} phx-change="filter" phx-submit="filter" class="relative flex-1 min-w-[220px]">
        <.icon name="hero-magnifying-glass" class="size-4 absolute left-2.5 top-2 opacity-60" />
        <input
          name="q"
          value={@q}
          placeholder={@placeholder}
          class="pv-input"
          phx-debounce="150"
          aria-label="Filter"
          autocomplete="off"
        />
      </form>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :tab, :string, required: true

  @doc "Table / Graph switch, like the dashboard's resource view switch."
  def view_toggle(assigns) do
    ~H"""
    <div class="pv-seg" role="group" aria-label="View">
      <button
        :for={
          {t, label, icon} <- [
            {"resources", "Table", "hero-table-cells"},
            {"graph", "Graph", "hero-share"}
          ]
        }
        type="button"
        phx-click="tab"
        phx-value-tab={t}
        aria-pressed={to_string(@tab == t)}
        title={label}
      >
        <.icon name={icon} class="size-4" /> <span class="max-sm:hidden">{label}</span>
      </button>
    </div>
    """
  end

  attr :rows, :list, required: true, doc: "ResourceTree rows"
  attr :selected, :string, default: nil
  attr :key, :string, default: nil, doc: "stack key sent with select and toggle"
  attr :base_depth, :integer, default: 0

  @doc "Resource rows with tree lines and expand/collapse, like parent/child resources."
  def resource_rows(assigns) do
    ~H"""
    <div
      :for={row <- @rows}
      class="pv-row"
      role="row"
      data-urn={row.resource.urn}
      data-depth={row.depth}
      aria-selected={to_string(@selected == row.resource.urn)}
      phx-click="select"
      phx-value-urn={row.resource.urn}
      phx-value-key={@key}
    >
      <span :for={_ <- 1..(row.depth + @base_depth)//1} class="pv-indent"></span>
      <button
        :if={row.children?}
        type="button"
        class="pv-icon-btn !size-5 -ml-1"
        data-toggle
        phx-click="toggle"
        phx-value-urn={row.resource.urn}
        phx-value-key={@key}
        aria-label={if row.collapsed?, do: "Expand", else: "Collapse"}
        aria-expanded={to_string(!row.collapsed?)}
      >
        <.icon
          name={if row.collapsed?, do: "hero-chevron-right-mini", else: "hero-chevron-down-mini"}
          class="size-4"
        />
      </button>
      <span :if={!row.children?} class="w-4"></span>
      <.icon name={provider_icon(row.resource.package)} class="size-4 text-primary shrink-0" />
      <span class="font-semibold truncate min-w-[8rem]">
        {if row.resource.protect, do: "🔒 "}{row.resource.name}
      </span>
      <span class="font-mono text-xs opacity-75 truncate flex-1 max-md:hidden">{row.resource.type}</span>
      <span class="font-mono text-xs opacity-75 truncate max-w-[18rem] max-lg:hidden">{row.resource.id}</span>
      <.icon name="hero-ellipsis-horizontal" class="size-4 opacity-60 shrink-0" />
    </div>
    """
  end

  attr :orientation, :string, required: true
  attr :open, :boolean, required: true
  slot :master, required: true
  slot :details

  @doc "Master/detail split with a resizable details panel, beside or below."
  def split(assigns) do
    ~H"""
    <div id="split" data-orientation={@orientation} class="flex-1 min-h-0 gap-0">
      <div class="pv-master pv-card">{render_slot(@master)}</div>
      <div
        :if={@open}
        id="splitter"
        class="pv-splitter"
        phx-hook="Splitter"
        role="separator"
        tabindex="0"
        aria-label="Resize the details panel"
        aria-orientation={if @orientation == "beside", do: "vertical", else: "horizontal"}
      >
      </div>
      <section
        :if={@open}
        id="details"
        data-orientation={@orientation}
        class="pv-card overflow-auto min-h-0"
        aria-label="Details"
      >
        {render_slot(@details)}
      </section>
    </div>
    """
  end

  attr :icon, :string, default: "hero-cube"
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block

  def details_header(assigns) do
    ~H"""
    <div class="sticky top-0 z-10 flex items-start gap-3 border-b border-base-300 bg-base-100 px-4 py-3">
      <span class="flex size-8 items-center justify-center rounded-md bg-base-200">
        <.icon name={@icon} class="size-5 text-primary" />
      </span>
      <div class="min-w-0 flex-1">
        <div class="truncate text-base font-semibold">{@title}</div>
        <div :if={@subtitle} class="truncate font-mono text-xs opacity-75">{@subtitle}</div>
      </div>
      {render_slot(@inner_block)}
      <button
        type="button"
        class="pv-icon-btn"
        phx-click="close"
        aria-label="Close details"
        title="Close"
      >
        <.icon name="hero-x-mark" class="size-5" />
      </button>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :title, :string, required: true
  attr :icon, :string, default: "hero-information-circle"
  attr :count, :integer, default: nil
  attr :open, :boolean, default: true
  attr :copy, :string, default: nil, doc: "text for the copy button"
  slot :inner_block, required: true

  @doc "A collapsible card section of the details panel."
  def section(assigns) do
    ~H"""
    <details class="pv-card m-3 group" data-section={@name} open={@open}>
      <summary class="flex cursor-pointer list-none items-center gap-2 px-4 py-3">
        <.icon name={@icon} class="size-4 text-primary" />
        <span class="font-semibold">{@title}</span>
        <span :if={@count} class="pv-count">{@count}</span>
        <span class="flex-1"></span>
        <button
          :if={@copy}
          type="button"
          class="pv-icon-btn !size-7"
          title="Copy"
          aria-label={"Copy #{@title}"}
          data-copy={@copy}
          onclick="event.preventDefault()"
          phx-click={JS.dispatch("pv:copy")}
        >
          <.icon name="hero-clipboard-document" class="size-4" />
        </button>
        <.icon name="hero-chevron-down-mini" class="size-4 transition group-open:rotate-180" />
      </summary>
      <div class="px-4 pb-3">{render_slot(@inner_block)}</div>
    </details>
    """
  end

  def pretty(term), do: Jason.encode!(term, pretty: true)

  def raw_map(r),
    do:
      Map.from_struct(r)
      |> Map.drop([
        :__meta__,
        :__metadata__,
        :__lateral_join_source__,
        :aggregates,
        :calculations
      ])

  def by_urn(resources, urn), do: Enum.find(resources, &(&1.urn == urn))

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :code, :string, required: true

  # Rendered in the browser by @pierre/diffs (the diffs.com code viewer). The <pre> is the
  # no-JS fallback and is replaced on mount.
  def code_block(assigns) do
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

  attr :r, :map, required: true
  attr :links, :list, required: true
  attr :resources, :list, required: true
  attr :stack, :map, default: nil, doc: "shown with a link on cross-stack pages"

  def resource_details(assigns) do
    ~H"""
    <.details_header icon={provider_icon(@r.package)} title={@r.name} subtitle={@r.type} />
    <.section name="resource" title="Resource" copy={@r.urn}>
      <dl class="pv-kv">
        <dt :if={@stack}>Stack</dt>
        <dd :if={@stack} class="!font-sans">
          <.link class="link link-primary" navigate={stack_path(@stack)}>{@stack.name}</.link>
          <span class="opacity-60">({@stack.source} · {env_label(@stack.environment)})</span>
        </dd>
        <dt>URN</dt><dd>{@r.urn}</dd>
        <dt :if={@r.id}>Physical ID</dt><dd :if={@r.id}>{@r.id}</dd>
        <dt>Type</dt><dd>{@r.type}</dd>
        <dt>Provider</dt><dd>{@r.provider_urn || @r.package}</dd>
        <dt :if={@r.parent_urn}>Parent</dt><dd :if={@r.parent_urn}>{@r.parent_urn}</dd>
        <dt>Protected</dt><dd>{if @r.protect, do: "yes", else: "no"}</dd>
      </dl>
    </.section>
    <.section name="links" title="Links" icon="hero-link" count={length(@links)} open={@links != []}>
      <dl class="pv-kv">
        <div :for={l <- @links} class="also-in contents">
          <dt>Also in</dt>
          <dd class="!font-sans">
            <.link
              class="link link-primary"
              navigate={~p"/sources/#{l.source}/stacks/#{l.project || "_"}/#{l.stack}"}
            >
              {kind_label(l.kind)} stack {l.stack}
            </.link>
            <span class="opacity-60">({l.source})</span>
          </dd>
        </div>
      </dl>
      <p :if={@links == []} class="text-xs opacity-70">
        No resource with this physical ID in another source.
      </p>
    </.section>
    <.section
      name="outputs"
      title="Outputs"
      icon="hero-arrow-up-tray"
      count={map_size(@r.outputs || %{})}
    >
      <.code_block id={"out-#{@r.urn}"} name="outputs.json" code={pretty(@r.outputs)} />
    </.section>
    <.section
      name="inputs"
      title="Inputs"
      icon="hero-arrow-down-tray"
      count={map_size(@r.inputs || %{})}
      open={false}
    >
      <.code_block id={"in-#{@r.urn}"} name="inputs.json" code={pretty(@r.inputs)} />
    </.section>
    <.section
      name="dependencies"
      title="Dependencies"
      icon="hero-share"
      count={length(@r.dependencies || [])}
    >
      <ul class="space-y-1">
        <li :for={d <- @r.dependencies || []}>
          <button
            type="button"
            class="link link-primary font-mono text-xs text-left break-all"
            phx-click="select"
            phx-value-urn={d}
          >
            {(by_urn(@resources, d) || %{name: d}).name}
          </button>
        </li>
      </ul>
      <p :if={(@r.dependencies || []) == []} class="text-xs opacity-70">No dependencies.</p>
    </.section>
    <.section name="raw" title="Raw resource" icon="hero-code-bracket" open={false}>
      <.code_block id={"raw-#{@r.urn}"} name="resource.json" code={pretty(raw_map(@r))} />
    </.section>
    """
  end

  attr :u, :map, required: true
  attr :stack, :map, default: nil

  def update_details(assigns) do
    ~H"""
    <.details_header icon="hero-clock" title={"Update #{@u.version}"} subtitle={@u.kind} />
    <.section name="update" title="Update">
      <dl class="pv-kv">
        <dt :if={@stack}>Stack</dt>
        <dd :if={@stack} class="!font-sans">
          <.link class="link link-primary" navigate={stack_path(@stack)}>{@stack.name}</.link>
          <span class="opacity-60">({@stack.source})</span>
        </dd>
        <dt>Result</dt><dd><span class="pv-chip" data-result={@u.result}>{@u.result}</span></dd>
        <dt>Kind</dt><dd>{@u.kind}</dd>
        <dt>Started</dt><dd>{time(@u.started_at)}</dd>
        <dt>Duration</dt><dd>{duration(@u.duration_s)}</dd>
        <dt>Message</dt><dd class="!font-sans">{@u.message}</dd>
      </dl>
    </.section>
    <.section
      name="changes"
      title="Changes"
      icon="hero-arrows-right-left"
      count={map_size(@u.changes || %{})}
    >
      <dl class="pv-kv">
        <%= for {k, v} <- Enum.sort(@u.changes || %{}) do %>
          <dt>{k}</dt><dd>{v}</dd>
        <% end %>
      </dl>
    </.section>
    """
  end
end

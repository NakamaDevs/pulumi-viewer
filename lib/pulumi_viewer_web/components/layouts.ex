defmodule PulumiViewerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PulumiViewerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :active, :atom, default: :stacks, doc: "the top bar tab of this page"
  attr :prefs, :map, default: PulumiViewerWeb.Prefs.defaults()
  attr :full, :boolean, default: false, doc: "fill the window height (master/detail pages)"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class={["flex flex-col", @full && "h-dvh"]}>
      <header class="pv-header flex items-center gap-2 px-3 shrink-0">
        <a href="/" class="flex items-center gap-2 pr-3 font-semibold text-[17px] whitespace-nowrap">
          <.icon name="hero-squares-2x2-solid" class="size-6 text-primary" />
          <span class="max-sm:hidden">Pulumi Viewer</span>
        </a>
        <nav class="flex items-center overflow-x-auto" aria-label="Main">
          <.link
            :for={{key, label, icon, path} <- tabs()}
            navigate={path}
            class="pv-tab"
            aria-current={@active == key && "page"}
          >
            <.icon name={icon} class="size-4" /> <span class="max-sm:hidden">{label}</span>
          </.link>
        </nav>
        <div class="ml-auto flex items-center gap-1">
          <details id="sources-menu" class="relative">
            <summary class="pv-icon-btn cursor-pointer list-none" title="Sources" aria-label="Sources">
              <.icon name="hero-circle-stack" class="size-5" />
            </summary>
            <div class="pv-card absolute right-0 top-10 z-50 w-max max-w-[90vw] p-3 space-y-1 shadow-lg">
              <div class="pv-section-title pb-1">Sources</div>
              <div
                :for={s <- PulumiViewer.sources_label()}
                class="font-mono text-xs"
                data-source-label
              >
                {s}
              </div>
            </div>
          </details>
          <a
            class="pv-icon-btn"
            href="https://github.com/NakamaDevs/pulumi-viewer#readme"
            target="_blank"
            rel="noopener"
            title="Help"
            aria-label="Help"
          >
            <.icon name="hero-question-mark-circle" class="size-5" />
          </a>
          <button
            type="button"
            class="pv-icon-btn"
            title="Settings"
            aria-label="Settings"
            id="settings-open"
            phx-click={open_settings()}
          >
            <.icon name="hero-cog-6-tooth" class="size-5" />
          </button>
        </div>
      </header>

      <main class={["p-3", @full && "flex-1 min-h-0 flex flex-col"]}>
        {render_slot(@inner_block)}
      </main>
    </div>

    <.settings prefs={@prefs} />
    <.flash_group flash={@flash} />
    """
  end

  defp tabs,
    do: [
      {:stacks, "Stacks", "hero-rectangle-stack", "/"},
      {:resources, "Resources", "hero-cube", "/resources"},
      {:history, "History", "hero-clock", "/history"}
    ]

  defp open_settings,
    do:
      JS.remove_attribute("hidden", to: "#settings-dialog")
      |> JS.remove_attribute("hidden", to: "#settings-scrim")
      |> JS.focus(to: "#settings-close")

  defp close_settings,
    do:
      JS.set_attribute({"hidden", ""}, to: "#settings-dialog")
      |> JS.set_attribute({"hidden", ""}, to: "#settings-scrim")
      |> JS.focus(to: "#settings-open")

  attr :prefs, :map, required: true

  # The settings sheet of the dashboard: same sections and segmented controls.
  # The Settings hook keeps the values in localStorage and tells the page.
  def settings(assigns) do
    ~H"""
    <div id="settings-scrim" class="pv-scrim" hidden phx-click={close_settings()}></div>
    <section
      id="settings-dialog"
      class="pv-sheet pv-card"
      role="dialog"
      aria-modal="true"
      aria-labelledby="settings-title"
      hidden
      phx-hook="Settings"
      phx-window-keydown={close_settings()}
      phx-key="Escape"
    >
      <div class="flex items-center justify-between px-5 pt-4 pb-2">
        <h2 id="settings-title" class="text-lg font-semibold">Settings</h2>
        <button
          id="settings-close"
          class="pv-icon-btn"
          aria-label="Close"
          phx-click={close_settings()}
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </div>
      <div class="flex-1 overflow-auto px-5 space-y-5">
        <div class="space-y-3">
          <div class="pv-section-title">Appearance</div>
          <.setting_row label="Theme">
            <div class="pv-seg">
              <button
                :for={
                  {v, label, icon} <- [
                    {"system", "System", "hero-computer-desktop"},
                    {"light", "Light", "hero-sun"},
                    {"dark", "Dark", "hero-moon"}
                  ]
                }
                type="button"
                data-phx-theme={v}
                phx-click={JS.dispatch("phx:set-theme")}
              >
                <.icon name={icon} class="size-4" /> {label}
              </button>
            </div>
          </.setting_row>
          <.setting_row label="Resource list density">
            <.pref_seg
              name="density"
              value={@prefs.density}
              options={[
                {"comfortable", "Comfortable", "hero-bars-3"},
                {"compact", "Compact", "hero-bars-4"}
              ]}
            />
          </.setting_row>
          <.setting_row label="Resources view">
            <.pref_seg
              name="view"
              value={@prefs.view}
              options={[{"table", "Table", "hero-table-cells"}, {"graph", "Graph", "hero-share"}]}
            />
          </.setting_row>
          <.setting_row label="Details panel">
            <.pref_seg
              name="orientation"
              value={@prefs.orientation}
              options={[{"beside", "Beside", "hero-view-columns"}, {"below", "Below", "hero-bars-2"}]}
            />
          </.setting_row>
        </div>
        <div class="space-y-2">
          <div class="pv-section-title">Sources</div>
          <div :for={s <- PulumiViewer.sources_label()} class="font-mono text-xs">{s}</div>
        </div>
      </div>
      <div class="flex items-end justify-between px-5 py-4 text-xs opacity-80">
        <div>Read-only. Settings are kept in this browser.</div>
        <button class="btn btn-primary btn-sm" phx-click={close_settings()}>Close</button>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp setting_row(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-2">
      <span class="font-semibold">{@label}</span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp pref_seg(assigns) do
    ~H"""
    <div class="pv-seg" role="group" aria-label={@name}>
      <button
        :for={{v, label, icon} <- @options}
        type="button"
        data-pref={@name}
        data-value={v}
        aria-pressed={to_string(@value == v)}
      >
        <.icon name={icon} class="size-4" /> {label}
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end

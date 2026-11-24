defmodule PulumiViewerWeb.PrefsHook do
  @moduledoc "Puts the layout options in `@prefs` and keeps them current when the settings change."
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    prefs =
      if connected?(socket),
        do: PulumiViewerWeb.Prefs.from_params(get_connect_params(socket)),
        else: PulumiViewerWeb.Prefs.defaults()

    {:cont,
     socket
     |> assign(prefs: prefs)
     |> attach_hook(:prefs, :handle_event, fn
       "prefs", params, socket ->
         old = socket.assigns.prefs
         prefs = PulumiViewerWeb.Prefs.from_params(%{"prefs" => params})
         {:halt, socket |> assign(prefs: prefs) |> on_prefs(old, prefs)}

       _, _, socket ->
         {:cont, socket}
     end)}
  end

  # a page may react, e.g. to show the graph after the view option changed
  defp on_prefs(socket, old, prefs) do
    if function_exported?(socket.view, :prefs_changed, 3),
      do: socket.view.prefs_changed(socket, old, prefs),
      else: socket
  end
end

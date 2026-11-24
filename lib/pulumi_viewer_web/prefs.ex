defmodule PulumiViewerWeb.Prefs do
  @moduledoc """
  Layout options of one viewer, like the Aspire dashboard settings. The browser keeps
  them in localStorage and sends them as LiveView connect params.
  """

  @allowed %{
    view: ~w(table graph),
    orientation: ~w(beside below),
    density: ~w(compact comfortable)
  }
  @defaults %{view: "table", orientation: "beside", density: "compact"}

  def defaults, do: @defaults

  def from_params(%{"prefs" => %{} = p}) do
    Map.new(@defaults, fn {k, default} ->
      v = p[Atom.to_string(k)]
      {k, if(v in @allowed[k], do: v, else: default)}
    end)
  end

  def from_params(_), do: @defaults
end

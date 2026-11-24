defmodule PulumiViewerWeb.PrefsTest do
  use ExUnit.Case, async: true
  alias PulumiViewerWeb.Prefs

  test "defaults match the dashboard defaults" do
    assert Prefs.from_params(nil) == %{view: "table", orientation: "beside", density: "compact"}
  end

  test "keeps known values from the browser" do
    assert Prefs.from_params(%{
             "prefs" => %{"view" => "graph", "orientation" => "below", "density" => "comfortable"}
           }) ==
             %{view: "graph", orientation: "below", density: "comfortable"}
  end

  test "drops unknown values" do
    assert Prefs.from_params(%{"prefs" => %{"view" => "x", "orientation" => 3, "density" => nil}}) ==
             Prefs.from_params(nil)
  end
end

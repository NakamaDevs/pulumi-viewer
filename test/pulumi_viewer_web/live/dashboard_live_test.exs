defmodule PulumiViewerWeb.DashboardLiveTest do
  @moduledoc "The Aspire-dashboard-like shell, pages and layout options."
  use PulumiViewerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  @stack_urn "urn:pulumi:dev::demo::pulumi:pulumi:Stack::demo-dev"
  @bucket_urn "urn:pulumi:dev::demo::aws:s3/bucketV2:BucketV2::assets"

  defp prefs(conn, p), do: put_connect_params(conn, %{"prefs" => p})

  test "top bar has the tabs, the sources menu and the settings dialog", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "header nav a[href='/'][aria-current='page']", "Stacks")
    assert has_element?(view, "header nav a[href='/resources']", "Resources")
    assert has_element?(view, "header nav a[href='/history']", "History")
    assert has_element?(view, "header #sources-menu [data-source-label]")
    assert has_element?(view, "#settings-dialog [data-phx-theme='system']")
    assert has_element?(view, "#settings-dialog [data-pref='density'][data-value='comfortable']")
    assert has_element?(view, "#settings-dialog [data-pref='view'][data-value='graph']")
    assert has_element?(view, "#settings-dialog [data-pref='orientation'][data-value='below']")
  end

  test "stacks are a tree list: environment rows that collapse, stack rows below", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#group-dev [data-group-toggle]")

    assert has_element?(
             view,
             "#group-dev [data-row='stack'] a[href='/sources/default/stacks/demo/dev']"
           )

    view |> element("#group-dev [data-group-toggle]") |> render_click()
    refute has_element?(view, "#group-dev [data-row='stack']")
  end

  test "stack page opens on the table; the toggle switches to the graph", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/stacks/demo/dev")
    assert has_element?(view, "#resource-list [data-urn='#{@bucket_urn}']")
    refute has_element?(view, "#graph")
    view |> element(~s|button[phx-value-tab="graph"]|) |> render_click()
    assert has_element?(view, ~s|#graph[phx-hook="ResourceGraph"]|)
  end

  test "the view option from the settings opens the graph first", %{conn: conn} do
    {:ok, view, _} = live(prefs(conn, %{"view" => "graph"}), ~p"/stacks/demo/dev")
    assert has_element?(view, "#graph")
  end

  test "children sit under their parent and collapse", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/stacks/demo/dev")
    assert has_element?(view, "#resource-list [data-urn='#{@bucket_urn}'][data-depth='1']")
    view |> element("#resource-list [data-urn='#{@stack_urn}'] [data-toggle]") |> render_click()
    refute has_element?(view, "#resource-list [data-urn='#{@bucket_urn}']")
  end

  test "a search finds resources under a collapsed parent", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/stacks/demo/dev")
    view |> element("#resource-list [data-urn='#{@stack_urn}'] [data-toggle]") |> render_click()
    view |> form("#filter", %{q: "policy"}) |> render_change()
    assert has_element?(view, "#resource-list", "assets-policy")
  end

  test "the filter box is only in the table view", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/stacks/demo/dev")
    view |> element(~s|button[phx-value-tab="graph"]|) |> render_click()
    refute has_element?(view, "#filter")
  end

  test "details panel sits beside or below, by the orientation option", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/stacks/demo/dev")
    render_hook(view, "select", %{"urn" => @bucket_urn})
    assert has_element?(view, "#details[data-orientation='beside'] [data-section='resource']")
    assert has_element?(view, "#details [data-section='outputs']")
    assert has_element?(view, "#details [data-section='dependencies']")
    assert has_element?(view, "#split [phx-hook='Splitter']")

    {:ok, view, _} = live(prefs(conn, %{"orientation" => "below"}), ~p"/stacks/demo/dev")
    render_hook(view, "select", %{"urn" => @bucket_urn})
    assert has_element?(view, "#details[data-orientation='below']")
    view |> element("#details button[phx-click='close']") |> render_click()
    refute has_element?(view, "#details")
  end

  test "resources page lists resources of all stacks, with a filter and details", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/resources")
    html = render_async(view)
    assert html =~ "assets-policy"
    assert has_element?(view, "[data-stack-group='default/demo/dev']")

    view |> form("#resource-filter", %{q: "policy"}) |> render_change()
    assert has_element?(view, "#resource-list", "assets-policy")
    refute has_element?(view, "#resource-list [data-urn='#{@bucket_urn}']")

    render_hook(view, "select", %{"key" => "default/demo/dev", "urn" => @stack_urn})
    assert has_element?(view, "#details [data-section='resource']", "pulumi:pulumi:Stack")
  end

  test "history page lists updates of all stacks and opens one", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/history")
    html = render_async(view)
    assert html =~ "add policy"
    assert has_element?(view, "#history [data-result='failed']")
    view |> element("#history tr[data-update]:first-child") |> render_click()
    assert has_element?(view, "#details [data-section='update']")
  end
end

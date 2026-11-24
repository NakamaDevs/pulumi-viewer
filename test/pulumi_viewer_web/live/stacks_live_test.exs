defmodule PulumiViewerWeb.StacksLiveTest do
  use PulumiViewerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "home lists the stacks of the backend", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "demo"
    assert html =~ "dev"
    assert html =~ "4 resources"
    assert has_element?(view, ~s|a[href="/sources/default/stacks/demo/dev"]|)
  end

  test "stack page shows graph, resources, history and a detail panel", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/stacks/demo/dev")
    assert has_element?(view, ~s|#graph[phx-hook="ResourceGraph"]|)
    assert html =~ "aws:s3/bucketV2:BucketV2"

    html = view |> element(~s|button[phx-value-tab="history"]|) |> render_click()
    assert html =~ "add policy"
    assert html =~ "failed"

    html =
      render_hook(view, "select", %{
        "urn" => "urn:pulumi:dev::demo::aws:s3/bucketV2:BucketV2::assets"
      })

    assert html =~ "arn:aws:s3:::assets-dev"
    assert html =~ "[secret]"
    # code panels render with the diffs.com viewer, from server-provided JSON
    assert has_element?(view, ~s|[phx-hook="CodeBlock"][data-name="outputs.json"]|)
    assert has_element?(view, ~s|[phx-hook="CodeBlock"][data-name="inputs.json"]|)
    assert has_element?(view, ~s|[phx-hook="CodeBlock"][data-name="resource.json"]|)
  end

  test "filters resources by text", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/stacks/demo/dev")
    view |> element(~s|button[phx-value-tab="resources"]|) |> render_click()
    html = view |> form("#filter", %{q: "policy"}) |> render_change()
    assert html =~ "assets-policy"
    refute html =~ "BucketV2::assets\""
  end

  test "unknown stack shows not found", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/stacks/demo/nope")
    assert html =~ "Stack not found"
  end
end

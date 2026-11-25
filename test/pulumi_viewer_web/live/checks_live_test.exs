defmodule PulumiViewerWeb.ChecksLiveTest do
  use PulumiViewerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    Application.put_env(:pulumi_viewer, :sources, "guarded=file://test/fixtures/guarded")
    Application.put_env(:pulumi_viewer, :inventory_dir, "test/fixtures/guarded/inventory")

    on_exit(fn ->
      Application.delete_env(:pulumi_viewer, :sources)
      Application.delete_env(:pulumi_viewer, :inventory_dir)
    end)
  end

  defp urn(name, type), do: "urn:pulumi:prod::bundle::#{type}::#{name}"

  test "resources show flags, owner and findings, and the flag filter works", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/resources")
    render_async(view)

    logs = "[data-urn='#{urn("logs", "aws:s3/bucketV2:BucketV2")}']"
    assets = "[data-urn='#{urn("assets", "aws:s3/bucketV2:BucketV2")}']"
    assert has_element?(view, "#{assets} [data-flag=retain]")
    assert has_element?(view, "#{logs} [data-kind=cloudformation]", "CFN")
    assert has_element?(view, "#{logs} [data-finding][data-sev=error]")
    refute has_element?(view, "#{logs} [data-flag=retain]")
    assert has_element?(view, "[data-urn$='::runner'] [data-flag=dbr]")
    assert has_element?(view, "#findings-error", "2 errors")

    view |> element("#resource-filter") |> render_change(%{"flag" => "unprotected"})
    assert has_element?(view, "[data-urn$='::jobs']")
    refute has_element?(view, assets)

    view |> element("#resource-filter") |> render_change(%{"flag" => "no-retain"})
    assert has_element?(view, logs)
    refute has_element?(view, assets)

    view |> element("#resource-filter") |> render_change(%{"flag" => "all"})
    view |> element(logs) |> render_click()
    assert has_element?(view, "[data-check=option_mismatch]", "retainOnDelete")
    assert render(view) =~ "CloudFormation (logs-stack)"
  end

  test "History shows the state edit with its resource change", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/history")
    render_async(view)
    assert has_element?(view, "tr[data-result='state edit']", "state edit")
    view |> element("tr[data-result='state edit']") |> render_click()
    assert has_element?(view, "[data-op='protect off']", "protect off")
    assert render(view) =~ "State edit"
  end
end

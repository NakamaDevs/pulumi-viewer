defmodule PulumiViewerWeb.CloudFormationLiveTest do
  use PulumiViewerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    prev = Application.get_env(:pulumi_viewer, :backend_url)
    Application.put_env(:pulumi_viewer, :backend_url, "cloudformation://us-east-1")

    Application.put_env(:pulumi_viewer, :cloudformation_aws_opts,
      http_client: PulumiViewer.CfnMock,
      access_key_id: "test",
      secret_access_key: "test",
      security_token: nil
    )

    PulumiViewer.CloudFormation.Cache.clear()

    on_exit(fn ->
      Application.put_env(:pulumi_viewer, :backend_url, prev)
      Application.delete_env(:pulumi_viewer, :cloudformation_aws_opts)
      :persistent_term.put({PulumiViewer.CfnMock, :mode}, :ok)
      PulumiViewer.CloudFormation.Cache.clear()
    end)
  end

  test "home shows the source and the CloudFormation stacks", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "cloudformation://us-east-1"
    assert html =~ "web-prod"
    assert html =~ "UPDATE_COMPLETE"
    assert has_element?(view, ~s|a[href="/sources/default/stacks/web/web-prod"]|)
  end

  test "stack page shows the graph, the stack outputs and the history", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/stacks/web/web-prod")
    assert html =~ "AWS::Lambda::Function"
    assert has_element?(view, ~s|#graph[phx-hook="ResourceGraph"]|)

    html = view |> element(~s|button[phx-value-tab="history"]|) |> render_click()
    assert html =~ "Bad handler"

    html = render_hook(view, "select", %{"urn" => "cfn:web-prod"})
    assert html =~ "arn:aws:lambda:fn"
  end

  test "home explains expired credentials", %{conn: conn} do
    :persistent_term.put({PulumiViewer.CfnMock, :mode}, :expired)
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "AWS credentials are expired"
    refute html =~ "Unknown Error"
  end

  test "stack page explains a credentials problem instead of not found", %{conn: conn} do
    :persistent_term.put({PulumiViewer.CfnMock, :mode}, :expired)
    {:ok, _view, html} = live(conn, ~p"/stacks/web/web-prod")
    assert html =~ "AWS credentials are expired"
  end
end

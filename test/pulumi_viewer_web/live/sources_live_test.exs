defmodule PulumiViewerWeb.SourcesLiveTest do
  use PulumiViewerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    Application.put_env(
      :pulumi_viewer,
      :backend_urls,
      "pulumi=file://test/fixtures/state,cfn=cloudformation://us-east-1"
    )

    Application.put_env(:pulumi_viewer, :cloudformation_aws_opts,
      http_client: PulumiViewer.CfnMock,
      access_key_id: "test",
      secret_access_key: "test",
      security_token: nil
    )

    PulumiViewer.CloudFormation.Cache.clear()

    on_exit(fn ->
      Application.delete_env(:pulumi_viewer, :backend_urls)
      Application.delete_env(:pulumi_viewer, :cloudformation_aws_opts)
      :persistent_term.put({PulumiViewer.CfnMock, :mode}, :ok)
      PulumiViewer.CloudFormation.Cache.clear()
    end)
  end

  test "home shows the stacks of all sources at the same time", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "file://test/fixtures/state"
    assert html =~ "cloudformation://us-east-1"
    assert has_element?(view, ~s|a[href="/stacks/demo/dev?source=pulumi"]|)
    assert has_element?(view, ~s|a[href="/stacks/web/web-prod?source=cfn"]|)
  end

  test "one failing source shows its error, the others still load", %{conn: conn} do
    :persistent_term.put({PulumiViewer.CfnMock, :mode}, :expired)
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "AWS credentials are expired"
    assert has_element?(view, ~s|a[href="/stacks/demo/dev?source=pulumi"]|)
  end

  test "a stack page reads from the source in the link", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/stacks/web/web-prod?source=cfn")
    assert html =~ "AWS::Lambda::Function"
    {:ok, _view, html} = live(conn, ~p"/stacks/demo/dev?source=pulumi")
    assert html =~ "aws:s3/bucketV2:BucketV2"
  end
end

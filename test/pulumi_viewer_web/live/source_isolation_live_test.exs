defmodule PulumiViewerWeb.SourceIsolationLiveTest do
  use PulumiViewerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    Application.put_env(:pulumi_viewer, :test_backends, %{
      "raise" => {PulumiViewer.FailingStorage, :raise},
      "exit" => {PulumiViewer.FailingStorage, :exit},
      "readraise" => {PulumiViewer.FailingStorage, :read_raises}
    })

    on_exit(fn ->
      Application.delete_env(:pulumi_viewer, :test_backends)
      Application.delete_env(:pulumi_viewer, :sources)
      Application.delete_env(:pulumi_viewer, :cloudformation_aws_opts)
      :persistent_term.put({PulumiViewer.CfnMock, :mode}, :ok)
      PulumiViewer.CloudFormation.Cache.clear()
    end)
  end

  test "a source that raises or exits shows its error; the healthy source still renders", %{
    conn: conn
  } do
    Application.put_env(
      :pulumi_viewer,
      :sources,
      "ok=file://test/fixtures/multi;bad=raise://x;gone=exit://x;broken=readraise://x"
    )

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#source-error-bad")
    assert has_element?(view, "#source-error-gone")
    assert has_element?(view, "a[href='/sources/ok/stacks/bundle/dev']")
    # a stack whose read raises still lists (0 resources); the source is not hidden
    refute has_element?(view, "#source-error-ok")
  end

  test "an error on one CloudFormation stack does not hide the source", %{conn: conn} do
    Application.put_env(:pulumi_viewer, :sources, "cfn=cloudformation://us-east-1")

    Application.put_env(:pulumi_viewer, :cloudformation_aws_opts,
      http_client: PulumiViewer.CfnMock,
      access_key_id: "test",
      secret_access_key: "test",
      security_token: nil
    )

    PulumiViewer.CloudFormation.Cache.clear()
    :persistent_term.put({PulumiViewer.CfnMock, :mode}, :stack_gone)
    {:ok, view, html} = live(conn, ~p"/")
    refute has_element?(view, "#source-error-cfn")
    assert has_element?(view, "a[href='/sources/cfn/stacks/web/web-prod']")
    assert html =~ "Stack does not exist"
  end

  test "a bad PULUMI_VIEWER_SOURCES is rejected by the startup check" do
    Application.put_env(:pulumi_viewer, :sources, "nope")
    assert_raise ArgumentError, fn -> PulumiViewer.Sources.validate!() end
  end
end

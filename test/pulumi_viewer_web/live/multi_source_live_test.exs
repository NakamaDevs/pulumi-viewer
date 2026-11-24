defmodule PulumiViewerWeb.MultiSourceLiveTest do
  use PulumiViewerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    Application.put_env(
      :pulumi_viewer,
      :sources,
      "pulumi=file://test/fixtures/multi;cloudformation=cloudformation://us-east-1"
    )

    Application.put_env(:pulumi_viewer, :cloudformation_aws_opts,
      http_client: PulumiViewer.CfnMock,
      access_key_id: "test",
      secret_access_key: "test",
      security_token: nil
    )

    PulumiViewer.CloudFormation.Cache.clear()

    on_exit(fn ->
      Application.delete_env(:pulumi_viewer, :sources)
      Application.delete_env(:pulumi_viewer, :cloudformation_aws_opts)
      :persistent_term.put({PulumiViewer.CfnMock, :mode}, :ok)
      PulumiViewer.CloudFormation.Cache.clear()
    end)
  end

  test "home groups stacks by environment, then account-wide, with source badges", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    # header lists every source
    assert html =~ "pulumi: file://test/fixtures/multi"
    assert html =~ "cloudformation: cloudformation://us-east-1"

    assert has_element?(view, "#group-dev a[href='/sources/pulumi/stacks/bundle/dev']")
    assert has_element?(view, "#group-prod a[href='/sources/cloudformation/stacks/web/web-prod']")
    assert has_element?(view, "#group-account a[href='/sources/pulumi/stacks/bundle/shared']")
    assert html =~ "Account-wide"
    assert html =~ "CloudFormation"
    assert html =~ "Pulumi"

    # environments come before the account-wide group
    [dev, prod, account] =
      Enum.map(~w(group-dev group-prod group-account), &(:binary.match(html, &1) |> elem(0)))

    assert dev < prod and prod < account
  end

  test "filters by environment and by source", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    html = view |> form("#filters", %{env: "prod"}) |> render_change()
    assert html =~ "web-prod"
    refute html =~ "/sources/pulumi/stacks/bundle/dev"

    html = view |> form("#filters", %{env: "all", source: "pulumi"}) |> render_change()
    refute html =~ "web-prod"
    assert html =~ "/sources/pulumi/stacks/bundle/dev"
  end

  test "a failing source shows its own error; the other sources still render", %{conn: conn} do
    :persistent_term.put({PulumiViewer.CfnMock, :mode}, :expired)
    {:ok, view, html} = live(conn, ~p"/")
    assert has_element?(view, "#source-error-cloudformation")
    assert html =~ "AWS credentials are expired"
    refute has_element?(view, "#source-error-pulumi")
    assert has_element?(view, "a[href='/sources/pulumi/stacks/bundle/dev']")
  end

  test "a resource with the same physical id links to the other source", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/sources/pulumi/stacks/bundle/dev")
    _ = render_async(view)

    html =
      render_hook(view, "select", %{
        "urn" => "urn:pulumi:dev::bundle::aws:iam/role:Role::role-dev"
      })

    assert html =~ "Also in"
    assert html =~ "CloudFormation stack web-prod"
    assert has_element?(view, ".also-in a[href='/sources/cloudformation/stacks/web/web-prod']")

    {:ok, view, _} = live(conn, ~p"/sources/cloudformation/stacks/web/web-prod")
    _ = render_async(view)
    html = render_hook(view, "select", %{"urn" => "cfn:web-prod::Role"})
    assert html =~ "Pulumi stack dev"
  end

  test "unknown source", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/sources/nope/stacks/bundle/dev")
    assert html =~ "Unknown source nope"
  end
end

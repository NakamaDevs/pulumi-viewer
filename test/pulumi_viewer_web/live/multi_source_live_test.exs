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
    {:ok, view, _html} = live(conn, ~p"/")
    # header lists every source
    assert has_element?(view, "header [data-source-label]", "pulumi: file://test/fixtures/multi")

    assert has_element?(
             view,
             "header [data-source-label]",
             "cloudformation: cloudformation://us-east-1"
           )

    assert has_element?(view, "#group-dev a[href='/sources/pulumi/stacks/bundle/dev']")
    assert has_element?(view, "#group-prod a[href='/sources/cloudformation/stacks/web/web-prod']")
    assert has_element?(view, "#group-account a[href='/sources/pulumi/stacks/bundle/shared']")
    assert has_element?(view, "#group-account h2", "Account-wide")

    assert has_element?(
             view,
             "a[href='/sources/cloudformation/stacks/web/web-prod'] [data-kind]",
             "CloudFormation"
           )

    assert has_element?(view, "a[href='/sources/pulumi/stacks/bundle/dev'] [data-kind]", "Pulumi")

    # environments come before the account-wide group
    ids =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("section[id^='group-']")
      |> LazyHTML.attribute("id")

    assert ids == ~w(group-dev group-prod group-account)
  end

  test "filters by environment and by source", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    view |> form("#filters", %{env: "prod"}) |> render_change()
    assert has_element?(view, "a[href='/sources/cloudformation/stacks/web/web-prod']")
    refute has_element?(view, "a[href='/sources/pulumi/stacks/bundle/dev']")

    view |> form("#filters", %{env: "all", source: "pulumi"}) |> render_change()
    refute has_element?(view, "a[href='/sources/cloudformation/stacks/web/web-prod']")
    assert has_element?(view, "a[href='/sources/pulumi/stacks/bundle/dev']")
  end

  test "a failing source shows its own error; the other sources still render", %{conn: conn} do
    :persistent_term.put({PulumiViewer.CfnMock, :mode}, :expired)
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#source-error-cloudformation", "AWS credentials are expired")
    refute has_element?(view, "#source-error-pulumi")
    assert has_element?(view, "a[href='/sources/pulumi/stacks/bundle/dev']")
  end

  test "a resource with the same physical id links to the other source", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/sources/pulumi/stacks/bundle/dev")
    _ = render_async(view)

    render_hook(view, "select", %{
      "urn" => "urn:pulumi:dev::bundle::aws:iam/role:Role::role-dev"
    })

    assert has_element?(view, ".also-in dt", "Also in")

    assert has_element?(
             view,
             ".also-in a[href='/sources/cloudformation/stacks/web/web-prod']",
             "CloudFormation stack web-prod"
           )

    {:ok, view, _} = live(conn, ~p"/sources/cloudformation/stacks/web/web-prod")
    _ = render_async(view)
    render_hook(view, "select", %{"urn" => "cfn:web-prod::Role"})

    assert has_element?(
             view,
             ".also-in a[href='/sources/pulumi/stacks/bundle/dev']",
             "Pulumi stack dev"
           )
  end

  test "unknown source", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sources/nope/stacks/bundle/dev")
    assert has_element?(view, "#stack-missing", "Unknown source nope")
  end
end

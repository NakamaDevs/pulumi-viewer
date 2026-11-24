defmodule PulumiViewer.SourcesTest do
  use ExUnit.Case, async: false
  alias PulumiViewer.Storage

  setup do
    prev =
      {Application.get_env(:pulumi_viewer, :backend_url),
       Application.get_env(:pulumi_viewer, :backend_urls)}

    Application.put_env(:pulumi_viewer, :cloudformation_aws_opts,
      http_client: PulumiViewer.CfnMock,
      access_key_id: "test",
      secret_access_key: "test",
      security_token: nil
    )

    PulumiViewer.CloudFormation.Cache.clear()

    on_exit(fn ->
      {u, us} = prev
      Application.put_env(:pulumi_viewer, :backend_url, u)

      if us,
        do: Application.put_env(:pulumi_viewer, :backend_urls, us),
        else: Application.delete_env(:pulumi_viewer, :backend_urls)

      Application.delete_env(:pulumi_viewer, :cloudformation_aws_opts)
      :persistent_term.put({PulumiViewer.CfnMock, :mode}, :ok)
      PulumiViewer.CloudFormation.Cache.clear()
    end)
  end

  test "parses a list of named sources, with a profile per source" do
    Application.put_env(
      :pulumi_viewer,
      :backend_urls,
      "dev=cloudformation://us-east-1?prefix=quickbuy-dev&profile=bundle-dev, prod=s3://state-prod/team?profile=bundle-prod,local=file://test/fixtures/state"
    )

    assert [
             %{
               name: "dev",
               mod: PulumiViewer.CloudFormation,
               cfg: %{region: "us-east-1", prefix: "quickbuy-dev", profile: "bundle-dev"}
             },
             %{
               name: "prod",
               mod: PulumiViewer.Storage.S3,
               cfg: %{bucket: "state-prod", prefix: "team", profile: "bundle-prod"}
             },
             %{name: "local", mod: PulumiViewer.Storage.Local}
           ] = Storage.sources()
  end

  test "a comma inside a query value stays in its URL" do
    Application.put_env(
      :pulumi_viewer,
      :backend_urls,
      "dev=cloudformation://us-east-1?prefix=a,b&profile=p,local=file://test/fixtures/state"
    )

    assert [%{name: "dev", cfg: %{prefix: "a,b", profile: "p"}}, %{name: "local"}] =
             Storage.sources()
  end

  test "an unknown URL or a duplicate name is an error of that source only" do
    Application.put_env(
      :pulumi_viewer,
      :backend_urls,
      "ok=file://test/fixtures/state,typo=ftp://x,ok=file://other"
    )

    assert [
             %{name: "ok", mod: PulumiViewer.Storage.Local},
             %{name: "typo", error: e1},
             %{name: "ok", error: e2}
           ] = Storage.sources()

    assert e1 =~ "ftp://x"
    assert e2 =~ "duplicate"
    assert [_] = PulumiViewer.Infra.list_stacks!("ok")
    assert {:error, _} = PulumiViewer.Infra.list_stacks("typo")
  end

  test "an empty list falls back to PULUMI_BACKEND_URL" do
    Application.put_env(:pulumi_viewer, :backend_urls, ",")
    Application.put_env(:pulumi_viewer, :backend_url, "file://test/fixtures/state")
    assert [%{name: "default"}] = Storage.sources()
  end

  test "a single PULUMI_BACKEND_URL is one source named default" do
    Application.delete_env(:pulumi_viewer, :backend_urls)
    Application.put_env(:pulumi_viewer, :backend_url, "file://test/fixtures/state")
    assert [%{name: "default", mod: PulumiViewer.Storage.Local}] = Storage.sources()
  end

  test "lists the stacks of each source on its own" do
    Application.put_env(
      :pulumi_viewer,
      :backend_urls,
      "pulumi=file://test/fixtures/state,cfn=cloudformation://us-east-1"
    )

    [pulumi] = PulumiViewer.Infra.list_stacks!("pulumi")
    assert pulumi.source == "pulumi"
    assert pulumi.name == "dev"

    [cfn] = PulumiViewer.Infra.list_stacks!("cfn")
    assert cfn.source == "cfn"
    assert cfn.name == "web-prod"

    assert [_ | _] = PulumiViewer.Infra.list_resources!("web", "web-prod", "cfn")
    assert [_ | _] = PulumiViewer.Infra.list_resources!("demo", "dev", "pulumi")
  end
end

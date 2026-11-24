defmodule PulumiViewer.CloudFormation.SourceTest do
  use ExUnit.Case, async: false
  alias PulumiViewer.CloudFormation.Cache

  setup do
    prev = Application.get_env(:pulumi_viewer, :backend_url)
    Application.put_env(:pulumi_viewer, :backend_url, "cloudformation://us-east-1")

    Application.put_env(:pulumi_viewer, :cloudformation_aws_opts,
      http_client: PulumiViewer.CfnMock,
      access_key_id: "test",
      secret_access_key: "test",
      security_token: nil
    )

    Cache.clear()
    :persistent_term.put({PulumiViewer.CfnMock, :mode}, :ok)

    on_exit(fn ->
      Application.put_env(:pulumi_viewer, :backend_url, prev)
      Application.delete_env(:pulumi_viewer, :cloudformation_aws_opts)
      :persistent_term.put({PulumiViewer.CfnMock, :mode}, :ok)
      Cache.clear()
    end)
  end

  test "parses the backend URL with an optional prefix" do
    assert {PulumiViewer.CloudFormation, %{region: "eu-west-1", prefix: "quickbuy-"}} =
             PulumiViewer.Storage.parse_url("cloudformation://eu-west-1?prefix=quickbuy-")

    assert {PulumiViewer.CloudFormation, %{region: "us-east-1", prefix: nil}} =
             PulumiViewer.Storage.parse_url("cloudformation://us-east-1")
  end

  test "lists live stacks, resources with edges, and history through Ash" do
    [stack] = PulumiViewer.Infra.list_stacks!()
    assert stack.project == "web"
    assert stack.name == "web-prod"
    assert stack.resource_count == 3

    resources = PulumiViewer.Infra.list_resources!("web", "web-prod")
    fun = Enum.find(resources, &(&1.name == "Fn"))
    role = Enum.find(resources, &(&1.name == "Role"))
    assert fun.dependencies == [role.urn]
    root = Enum.find(resources, &(&1.type == "AWS::CloudFormation::Stack"))
    assert root.outputs == %{"FnArn" => "arn:aws:lambda:fn"}

    assert [%{kind: "update", result: "failed"}, %{kind: "create"}] =
             PulumiViewer.Infra.list_updates!("web", "web-prod")
  end

  test "caches responses" do
    c = :counters.new(1, [])
    :persistent_term.put({PulumiViewer.CfnMock, :calls}, c)
    PulumiViewer.Infra.list_stacks!()
    first = :counters.get(c, 1)
    assert first > 0
    PulumiViewer.Infra.list_stacks!()
    assert :counters.get(c, 1) == first
    :persistent_term.erase({PulumiViewer.CfnMock, :calls})
  end

  test "retries a throttled call" do
    :persistent_term.put({PulumiViewer.CfnMock, :mode}, {:throttle_once, make_ref()})
    assert [_] = PulumiViewer.Infra.list_stacks!()
  end

  test "explains expired credentials" do
    :persistent_term.put({PulumiViewer.CfnMock, :mode}, :expired)
    assert {:error, e} = PulumiViewer.Infra.list_stacks()
    assert Exception.message(e) =~ "AWS credentials are expired"
  end
end

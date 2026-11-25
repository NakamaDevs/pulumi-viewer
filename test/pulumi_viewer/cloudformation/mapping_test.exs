defmodule PulumiViewer.CloudFormation.MappingTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.CloudFormation.Mapping

  test "maps a stack name to a project by its first segment" do
    assert Mapping.project("quickbuy-prod-site") == "quickbuy"
    assert Mapping.project("wayfair-prod") == "wayfair"
    assert Mapping.project("standalone") == "cloudformation"
  end

  test "keeps only live stacks that match the prefix" do
    summaries = [
      %{"StackName" => "quickbuy-dev", "StackStatus" => "UPDATE_COMPLETE"},
      %{"StackName" => "quickbuy-old", "StackStatus" => "DELETE_COMPLETE"},
      %{"StackName" => "wayfair-prod", "StackStatus" => "CREATE_COMPLETE"}
    ]

    assert [%{project: "quickbuy", stack: "quickbuy-dev"}, %{stack: "wayfair-prod"}] =
             Mapping.stacks(summaries, nil)

    assert [%{stack: "quickbuy-dev"}] = Mapping.stacks(summaries, "quickbuy-")
  end

  test "groups stack events into updates, newest first" do
    events = Jason.decode!(File.read!("test/fixtures/cloudformation/events.json"))
    [update, create] = Mapping.updates(events)

    assert update.version == 2
    assert update.kind == "update"
    assert update.result == "failed"
    assert update.message =~ "Bad handler"
    assert update.duration_s == 300

    assert create.version == 1
    assert create.kind == "create"
    assert create.result == "succeeded"
    assert create.changes == %{"create" => 2}

    assert create.resources == [
             %{op: "create", name: "Fn", type: "AWS::Lambda::Function"},
             %{op: "create", name: "Role", type: "AWS::IAM::Role"}
           ]

    assert update.resources == []
    assert create.started_at == ~U[2026-11-01 09:00:00Z]
  end

  test "builds a checkpoint with resources, edges and stack outputs" do
    {:ok, t} =
      PulumiViewer.CloudFormation.Template.parse(
        File.read!("test/fixtures/cloudformation/template.json")
      )

    stack = %{
      "StackName" => "web",
      "StackStatus" => "UPDATE_COMPLETE",
      "LastUpdatedTime" => "2026-11-02T10:05:00Z",
      "Outputs" => [%{"OutputKey" => "FnArn", "OutputValue" => "arn:aws:lambda:x"}]
    }

    resources = [
      %{
        "LogicalResourceId" => "Role",
        "PhysicalResourceId" => "r-1",
        "ResourceType" => "AWS::IAM::Role",
        "ResourceStatus" => "CREATE_COMPLETE"
      },
      %{
        "LogicalResourceId" => "Fn",
        "PhysicalResourceId" => "fn-1",
        "ResourceType" => "AWS::Lambda::Function",
        "ResourceStatus" => "UPDATE_COMPLETE"
      }
    ]

    cp = Mapping.checkpoint(stack, resources, t)
    assert cp.updated_at == ~U[2026-11-02 10:05:00Z]
    assert cp.pulumi_version == "UPDATE_COMPLETE"
    [root, role, fun] = cp.resources
    assert root.type == "AWS::CloudFormation::Stack"
    assert root.outputs == %{"FnArn" => "arn:aws:lambda:x"}
    assert role.package == "iam"
    assert fun.id == "fn-1"
    assert fun.dependencies == [role.urn]
    assert fun.inputs["Role"] == %{"Fn::GetAtt" => ["Role", "Arn"]}
    assert fun.outputs["ResourceStatus"] == "UPDATE_COMPLETE"
  end

  test "a stack-level consistency check in the middle does not split the update" do
    ev = fn t, id, type, status, reason ->
      %{
        "Timestamp" => "2026-09-23T15:01:#{t}Z",
        "StackName" => "roles",
        "LogicalResourceId" => id,
        "ResourceType" => type,
        "ResourceStatus" => status,
        "ResourceStatusReason" => reason
      }
    end

    stack = "AWS::CloudFormation::Stack"
    role = "AWS::IAM::Role"

    events =
      Enum.reverse([
        ev.("10", "roles", stack, "CREATE_IN_PROGRESS", "User Initiated"),
        ev.("20", "A", role, "CREATE_IN_PROGRESS", ""),
        ev.("30", "A", role, "CREATE_COMPLETE", ""),
        ev.("40", "roles", stack, "CREATE_IN_PROGRESS", "Eventual consistency check initiated"),
        ev.("41", "B", role, "CREATE_COMPLETE", ""),
        ev.("50", "roles", stack, "CREATE_COMPLETE", "")
      ])

    assert [u] = Mapping.updates(events)
    assert u.result == "succeeded"
    assert u.message == "User Initiated"
    assert u.changes == %{"create" => 2}
    assert u.duration_s == 40
  end
end

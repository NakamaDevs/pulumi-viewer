defmodule PulumiViewer.Pulumi.DiffTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.Pulumi.Diff

  defp r(name, type, id, inputs \\ %{}),
    do: %{
      urn: "urn:pulumi:dev::p::#{type}::#{name}",
      name: name,
      type: type,
      id: id,
      inputs: inputs,
      outputs: %{}
    }

  test "lists created, updated, replaced and deleted resources, not unchanged ones" do
    before = [
      r("bucket", "aws:s3/bucketV2:BucketV2", "b-1", %{"tags" => %{"a" => "1"}}),
      r("role", "aws:iam/role:Role", "r-1"),
      r("fn", "aws:lambda/function:Function", "f-1"),
      r("same", "aws:sns/topic:Topic", "t-1")
    ]

    after_ = [
      r("bucket", "aws:s3/bucketV2:BucketV2", "b-1", %{"tags" => %{"a" => "2"}}),
      r("fn", "aws:lambda/function:Function", "f-2"),
      r("same", "aws:sns/topic:Topic", "t-1"),
      r("queue", "aws:sqs/queue:Queue", "q-1")
    ]

    assert Diff.changed(before, after_, %{}) == [
             %{op: "create", name: "queue", type: "aws:sqs/queue:Queue"},
             %{op: "delete", name: "role", type: "aws:iam/role:Role"},
             %{op: "replace", name: "fn", type: "aws:lambda/function:Function"},
             %{op: "update", name: "bucket", type: "aws:s3/bucketV2:BucketV2"}
           ]
  end

  test "new resources of an import update are imports" do
    assert [%{op: "import", name: "q"}] =
             Diff.changed([], [r("q", "aws:sqs/queue:Queue", "q-1")], %{"import" => 1})
  end

  test "an import update creates the stack and provider resources, it does not import them" do
    after_ = [
      r("bundle-dev", "pulumi:pulumi:Stack", nil),
      r("default_7_54_0", "pulumi:providers:aws", "p-1"),
      r("vpc", "aws:ec2/vpc:Vpc", "vpc-1")
    ]

    assert Diff.changed([], after_, %{"import" => 1, "create" => 1}) == [
             %{op: "create", name: "bundle-dev", type: "pulumi:pulumi:Stack"},
             %{op: "create", name: "default_7_54_0", type: "pulumi:providers:aws"},
             %{op: "import", name: "vpc", type: "aws:ec2/vpc:Vpc"}
           ]
  end
end

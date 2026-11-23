defmodule PulumiViewer.Pulumi.CheckpointTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.Pulumi.Checkpoint

  @json File.read!("test/fixtures/state/.pulumi/stacks/demo/dev.json")

  test "parses stack name, update time and resources" do
    {:ok, cp} = Checkpoint.parse(@json)
    assert cp.stack == "organization/demo/dev"
    assert cp.updated_at == ~U[2026-11-20 10:00:00.000Z]
    assert cp.pulumi_version == "v3.200.0"
    assert length(cp.resources) == 4
  end

  test "derives name, package and module from the URN and type" do
    {:ok, cp} = Checkpoint.parse(@json)
    bucket = Enum.find(cp.resources, &(&1.name == "assets"))
    assert bucket.type == "aws:s3/bucketV2:BucketV2"
    assert bucket.package == "aws"
    assert bucket.module == "s3"
    assert bucket.id == "assets-dev"
    assert bucket.protect
    assert bucket.custom
    assert bucket.provider_urn == "urn:pulumi:dev::demo::pulumi:providers:aws::default_6_0_0"
  end

  test "masks secret values" do
    {:ok, cp} = Checkpoint.parse(@json)
    bucket = Enum.find(cp.resources, &(&1.name == "assets"))
    assert bucket.outputs["apiKey"] == "[secret]"
    assert bucket.outputs["arn"] == "arn:aws:s3:::assets-dev"
  end

  test "accepts gzipped content and rejects garbage" do
    assert {:ok, %{resources: [_ | _]}} = Checkpoint.parse(:zlib.gzip(@json))
    assert {:error, _} = Checkpoint.parse("not json")
  end

  test "an empty stack has no resources" do
    json = ~s({"version":3,"checkpoint":{"stack":"organization/demo/empty","latest":null}})
    assert {:ok, %{resources: [], updated_at: nil}} = Checkpoint.parse(json)
  end
end

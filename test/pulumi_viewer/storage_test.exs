defmodule PulumiViewer.StorageTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.Storage.Local

  @root "test/fixtures/state"

  test "lists keys recursively and reads them" do
    keys = Local.list(@root, ".pulumi/")
    assert ".pulumi/stacks/demo/dev.json" in keys
    assert ".pulumi/meta.yaml" in keys
    assert {:ok, "version: 1\n"} = Local.read(@root, ".pulumi/meta.yaml")
    assert {:error, _} = Local.read(@root, ".pulumi/missing.json")
  end

  test "parses backend URLs" do
    assert PulumiViewer.Storage.parse_url("file://test/fixtures/state") ==
             {Local, "test/fixtures/state"}

    assert {PulumiViewer.Storage.S3, %{bucket: "my-state", prefix: "team"}} =
             PulumiViewer.Storage.parse_url("s3://my-state/team")
  end
end

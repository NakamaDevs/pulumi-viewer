defmodule PulumiViewer.InfraTest do
  use ExUnit.Case, async: false

  setup do
    prev = Application.get_env(:pulumi_viewer, :backend_url)
    Application.put_env(:pulumi_viewer, :backend_url, "file://test/fixtures/state")
    on_exit(fn -> Application.put_env(:pulumi_viewer, :backend_url, prev) end)
  end

  test "lists stacks through Ash" do
    [stack] = PulumiViewer.Infra.list_stacks!()
    assert stack.project == "demo"
    assert stack.name == "dev"
    assert stack.resource_count == 4
  end

  test "reads resources and updates of one stack through Ash" do
    resources = PulumiViewer.Infra.list_resources!("demo", "dev")
    assert Enum.any?(resources, &(&1.type == "aws:s3/bucketV2:BucketV2"))

    [newest, older] = PulumiViewer.Infra.list_updates!("demo", "dev")
    assert newest.version == 7
    assert older.result == "failed"
  end
end

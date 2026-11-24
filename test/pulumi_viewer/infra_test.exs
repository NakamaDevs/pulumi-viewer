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

defmodule PulumiViewer.InfraFreshStateTest do
  use ExUnit.Case, async: false

  test "Pulumi state is read again on each load (no cache across page loads)" do
    dir = Path.join(System.tmp_dir!(), "pv-fresh-#{System.unique_integer([:positive])}")
    stacks = Path.join(dir, ".pulumi/stacks/bundle")
    File.mkdir_p!(stacks)
    File.cp!("test/fixtures/multi/.pulumi/stacks/bundle/dev.json", Path.join(stacks, "dev.json"))
    Application.put_env(:pulumi_viewer, :sources, "p=file://#{dir}")

    on_exit(fn ->
      Application.delete_env(:pulumi_viewer, :sources)
      File.rm_rf!(dir)
    end)

    assert ["dev"] = PulumiViewer.Infra.list_stacks!("p") |> Enum.map(& &1.name)
    File.cp!(Path.join(stacks, "dev.json"), Path.join(stacks, "prod.json"))

    assert ["dev", "prod"] =
             PulumiViewer.Infra.list_stacks!("p") |> Enum.map(& &1.name) |> Enum.sort()
  end
end

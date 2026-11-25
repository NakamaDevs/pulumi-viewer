defmodule PulumiViewer.StateEditTest do
  use ExUnit.Case, async: false

  setup do
    Application.put_env(
      :pulumi_viewer,
      :sources,
      "guarded=file://test/fixtures/guarded;demo=file://test/fixtures/state"
    )

    on_exit(fn -> Application.delete_env(:pulumi_viewer, :sources) end)
  end

  test "a state change outside an update shows as a state edit at the top of History" do
    [edit, update] = PulumiViewer.Infra.list_updates!("bundle", "prod", "guarded")
    assert edit.kind == "state edit"
    assert edit.version == 0
    assert edit.result == "state edit"
    assert edit.resources == [%{op: "protect off", name: "jobs", type: "aws:sqs/queue:Queue"}]
    # the newest backup newer than the last update gives the time
    assert edit.started_at == DateTime.from_unix!(1_764_048_000)
    assert update.version == 3
  end

  test "no state edit while the stack has a lock (an update runs)" do
    dir = Path.join(System.tmp_dir!(), "pv-lock-#{System.unique_integer([:positive])}")
    File.cp_r!("test/fixtures/guarded", dir)
    File.mkdir_p!(Path.join(dir, ".pulumi/locks/bundle/prod"))
    File.write!(Path.join(dir, ".pulumi/locks/bundle/prod/x.json"), "{}")
    Application.put_env(:pulumi_viewer, :sources, "locked=file://#{dir}")
    on_exit(fn -> File.rm_rf!(dir) end)
    assert [%{version: 3}] = PulumiViewer.Infra.list_updates!("bundle", "prod", "locked")
  end

  test "no state edit when the state equals the last update" do
    assert [%{version: 7}, _] = PulumiViewer.Infra.list_updates!("demo", "dev", "demo")
  end
end

defmodule PulumiViewer.ChecksForStackTest do
  use ExUnit.Case, async: false

  setup do
    Application.put_env(:pulumi_viewer, :sources, "guarded=file://test/fixtures/guarded")
    Application.put_env(:pulumi_viewer, :inventory_dir, "test/fixtures/guarded/inventory")

    on_exit(fn ->
      Application.delete_env(:pulumi_viewer, :sources)
      Application.delete_env(:pulumi_viewer, :inventory_dir)
    end)
  end

  test "for_stack gives flags, owners and all findings, with the state edit" do
    {:ok, %{resources: rs, findings: fs}} =
      PulumiViewer.Checks.for_stack("guarded", "bundle", "prod")

    assert %{owner: %{kind: :cloudformation, name: "logs-stack"}, retain_on_delete: false} =
             Enum.find(rs, &(&1.name == "logs"))

    assert %{check: :state_edit, name: "jobs", message: "Changed outside an update: protect off."} =
             Enum.find(fs, &(&1.check == :state_edit))

    assert Enum.count(fs) == 6
  end
end

defmodule PulumiViewer.ChecksTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.{Checks, Inventory}
  alias PulumiViewer.Pulumi.Checkpoint

  @dir "test/fixtures/guarded"

  defp resources(file \\ ".pulumi/stacks/bundle/prod.json") do
    {:ok, cp} = Checkpoint.parse(File.read!(Path.join(@dir, file)))
    cp.resources
  end

  defp by_name(rs, name), do: Enum.find(rs, &(&1.name == name))

  test "the checkpoint parser reads protect, retainOnDelete and deleteBeforeReplace" do
    rs = resources()

    assert %{protect: true, retain_on_delete: true, delete_before_replace: false} =
             by_name(rs, "assets")

    assert %{protect: true, retain_on_delete: false} = by_name(rs, "logs")
    assert %{protect: false} = by_name(rs, "jobs")
    assert %{delete_before_replace: true} = by_name(rs, "runner")
  end

  test "the inventory gives the owner of each resource by type and name" do
    inv = Inventory.load(Path.join(@dir, "inventory"), "prod")
    assert Inventory.owner(inv, by_name(resources(), "logs")) == "cloudformation:logs-stack"
    assert Inventory.owner(inv, by_name(resources(), "jobs")) == nil
    assert Inventory.load(Path.join(@dir, "inventory"), "missing") == %{}
    assert Inventory.load(nil, "prod") == %{}
  end

  test "owner: CloudFormation from the inventory or a CloudFormation link, else Pulumi" do
    rs = resources()
    inv = Inventory.load(Path.join(@dir, "inventory"), "prod")

    links = %{
      "runner-role" => [%{source: "cfn", kind: :cloudformation, project: nil, stack: "iam"}]
    }

    assert Checks.owner(by_name(rs, "logs"), inv, links) == %{
             kind: :cloudformation,
             name: "logs-stack"
           }

    assert Checks.owner(by_name(rs, "runner"), inv, links) ==
             %{kind: :cloudformation, name: "iam", by: :link}

    assert Checks.owner(by_name(rs, "alerts"), inv, links) == %{
             kind: :other,
             name: "script:wayfair-v1"
           }

    assert Checks.owner(by_name(rs, "jobs"), inv, links) == %{kind: :pulumi, name: nil}
  end

  test "finds option mismatches, double owners and unprotected resources" do
    inv = Inventory.load(Path.join(@dir, "inventory"), "prod")
    findings = Checks.run(resources(), inventory: inv, links: %{})
    got = findings |> Enum.map(&{&1.check, &1.name}) |> Enum.sort()

    assert got == [
             {:double_owner, "assets"},
             {:double_owner, "logs"},
             {:option_mismatch, "alerts"},
             {:option_mismatch, "logs"},
             {:unprotected, "jobs"}
           ]

    logs = Enum.find(findings, &(&1.check == :option_mismatch and &1.name == "logs"))
    assert logs.severity == :error
    assert logs.message =~ "retainOnDelete"

    assert Enum.find(findings, &(&1.check == :double_owner and &1.name == "assets")).severity ==
             :info

    assert Enum.find(findings, &(&1.check == :double_owner and &1.name == "logs")).severity ==
             :error
  end

  test "an expected-options file overrides the owner rule" do
    expected = %{
      {"aws:sqs/queue:Queue", "jobs"} => %{"protect" => true, "retainOnDelete" => true}
    }

    findings = Checks.run(resources(), inventory: %{}, links: %{}, expected: expected)
    jobs = Enum.find(findings, &(&1.check == :option_mismatch))
    assert jobs.name == "jobs"
    assert jobs.message =~ "protect"
    assert jobs.message =~ "retainOnDelete"
  end

  test "a CloudFormation owner found only by physical ID gives info, never an option error" do
    links = %{
      "runner-role" => [%{source: "cfn", kind: :cloudformation, project: nil, stack: "iam"}]
    }

    fs =
      Checks.run(resources(), inventory: %{}, links: links) |> Enum.filter(&(&1.name == "runner"))

    assert [%{check: :double_owner, severity: :info}] = fs
  end

  test "a malformed inventory gives an empty map" do
    dir = Path.join(System.tmp_dir!(), "pv-inv-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, "prod.json"),
      ~s({"components": {"a": "oops", "b": [{"type": 1}]}})
    )

    on_exit(fn -> File.rm_rf!(dir) end)
    assert Inventory.load(dir, "prod") == %{}
  end

  test "no unprotected finding when most resources are not protected" do
    rs = resources() |> Enum.map(&%{&1 | protect: false})
    refute Enum.any?(Checks.run(rs, inventory: %{}, links: %{}), &(&1.check == :unprotected))
  end

  test "flag changes between two checkpoints" do
    before = resources(".pulumi/history/bundle/prod/prod-1764000000000000000.checkpoint.json")

    assert [%{op: "protect off", name: "jobs"}] =
             PulumiViewer.Pulumi.Diff.changed(before, resources(), %{})
  end
end

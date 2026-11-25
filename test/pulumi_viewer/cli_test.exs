defmodule PulumiViewer.CLITest do
  use ExUnit.Case, async: false
  alias PulumiViewer.CLI

  setup do
    Application.put_env(
      :pulumi_viewer,
      :sources,
      "guarded=file://test/fixtures/guarded;demo=file://test/fixtures/state"
    )

    Application.put_env(:pulumi_viewer, :inventory_dir, "test/fixtures/guarded/inventory")

    on_exit(fn ->
      Application.delete_env(:pulumi_viewer, :sources)
      Application.delete_env(:pulumi_viewer, :inventory_dir)
    end)
  end

  test "checks of one stack at warning or above, exit 1" do
    {1, %{stacks: [st]}} = CLI.run(~w(checks --stack bundle/prod --min warning))
    assert st.stack == "prod"

    assert Enum.map(st.findings, & &1.check) |> Enum.sort() ==
             [:double_owner, :option_mismatch, :option_mismatch, :state_edit, :unprotected]

    assert Jason.encode!(st)
  end

  test "checks of a clean stack, exit 0" do
    assert {0, %{stacks: [%{stack: "dev", findings: []}]}} =
             CLI.run(~w(checks --source demo --min warning))
  end

  test "flags lists each resource with its options and owner" do
    {0, %{resources: rs}} = CLI.run(~w(flags --stack bundle/prod))
    assert %{protect: false, owner: %{kind: :pulumi}} = Enum.find(rs, &(&1.name == "jobs"))
  end

  test "usage error" do
    assert {2, %{error: _}} = CLI.run(["nope"])
  end
end

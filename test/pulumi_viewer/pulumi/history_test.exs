defmodule PulumiViewer.Pulumi.HistoryTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.Pulumi.History

  test "parses one update" do
    json =
      File.read!(
        "test/fixtures/state/.pulumi/history/demo/dev/dev-1763632800000000000.history.json"
      )

    {:ok, u} = History.parse(json)
    assert u.kind == "update"
    assert u.result == "succeeded"
    assert u.version == 7
    assert u.message == "add policy"
    assert u.started_at == ~U[2025-11-20 10:00:00Z]
    assert u.duration_s == 60
    assert u.changes == %{"create" => 1, "same" => 3}
  end
end

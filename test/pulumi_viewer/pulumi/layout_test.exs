defmodule PulumiViewer.Pulumi.LayoutTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.Pulumi.Layout

  test "finds project-scoped and legacy stacks, plain and gzipped" do
    keys = [
      ".pulumi/meta.yaml",
      ".pulumi/stacks/demo/dev.json",
      ".pulumi/stacks/demo/dev.json.bak",
      ".pulumi/stacks/infra/prod.json.gz",
      ".pulumi/stacks/legacy.json",
      ".pulumi/history/demo/dev/dev-1.history.json"
    ]

    assert Layout.stacks(keys) == [
             %{project: "demo", stack: "dev", key: ".pulumi/stacks/demo/dev.json"},
             %{project: "infra", stack: "prod", key: ".pulumi/stacks/infra/prod.json.gz"},
             %{project: nil, stack: "legacy", key: ".pulumi/stacks/legacy.json"}
           ]
  end

  test "history prefix and history keys newest first" do
    assert Layout.history_prefix("demo", "dev") == ".pulumi/history/demo/dev/"

    keys = [
      ".pulumi/history/demo/dev/dev-1.history.json",
      ".pulumi/history/demo/dev/dev-1.checkpoint.json",
      ".pulumi/history/demo/dev/dev-3.history.json"
    ]

    assert Layout.history_keys(keys) == [
             ".pulumi/history/demo/dev/dev-3.history.json",
             ".pulumi/history/demo/dev/dev-1.history.json"
           ]
  end
end

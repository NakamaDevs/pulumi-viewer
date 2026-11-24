defmodule PulumiViewer.ResourceTreeTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.ResourceTree

  defp r(urn, parent \\ nil, name \\ nil),
    do: %{urn: urn, parent_urn: parent, name: name || urn, type: "t:#{urn}", id: nil}

  test "orders children under their parent with depth and a has-children flag" do
    rows = ResourceTree.flatten([r("c", "a"), r("b"), r("a"), r("d", "c")])

    assert Enum.map(rows, &{&1.resource.urn, &1.depth, &1.children?}) ==
             [{"a", 0, true}, {"c", 1, true}, {"d", 2, false}, {"b", 0, false}]
  end

  test "a parent that is not in the list makes the child a root" do
    assert [%{depth: 0}] = ResourceTree.flatten([r("x", "missing")])
  end

  test "collapsed parents hide all their descendants" do
    rows = ResourceTree.flatten([r("a"), r("c", "a"), r("d", "c"), r("b")], MapSet.new(["a"]))
    assert Enum.map(rows, & &1.resource.urn) == ["a", "b"]
    assert hd(rows).collapsed?
  end

  test "a text filter keeps the matches and their ancestors" do
    rows =
      ResourceTree.flatten([r("a"), r("c", "a", "policy"), r("b")]) |> ResourceTree.filter("POL")

    assert Enum.map(rows, & &1.resource.urn) == ["a", "c"]
  end

  test "an empty filter keeps all rows" do
    rows = ResourceTree.flatten([r("a"), r("b")])
    assert ResourceTree.filter(rows, "") == rows
  end
end

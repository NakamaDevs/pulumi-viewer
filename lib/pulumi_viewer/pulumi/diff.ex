defmodule PulumiViewer.Pulumi.Diff do
  @moduledoc """
  The resources one update changed: the difference between the checkpoint before the update
  and the checkpoint after it, by URN. Unchanged resources are left out.
  """

  @stack_type "pulumi:pulumi:Stack"

  @doc "`changes` is the update's resourceChanges; new resources of an import update are imports."
  def changed(before, after_, changes) do
    old = Map.new(before, &{&1.urn, &1})
    new = Map.new(after_, &{&1.urn, &1})
    added_op = if Map.has_key?(changes || %{}, "import"), do: "import", else: "create"

    added =
      for {urn, r} <- new, not Map.has_key?(old, urn), do: item(added_op(added_op, r), r)

    deleted = for {urn, r} <- old, not Map.has_key?(new, urn), do: item("delete", r)

    modified =
      for {urn, r} <- new, o = old[urn], op = op(o, r), do: item(op, r)

    Enum.sort_by(added ++ deleted ++ modified, &{&1.op, &1.name})
  end

  defp op(%{id: a}, %{id: b}) when a != b and not is_nil(a) and not is_nil(b), do: "replace"

  defp op(o, r) do
    cond do
      o.inputs != r.inputs -> "update"
      r.type == @stack_type and o.outputs != r.outputs -> "update"
      true -> nil
    end
  end

  # Pulumi creates the stack resource and providers; it never imports them.
  defp added_op("import", %{type: @stack_type}), do: "create"
  defp added_op("import", %{type: "pulumi:providers:" <> _}), do: "create"
  defp added_op(op, _), do: op

  defp item(op, r), do: %{op: op, name: r.name, type: r.type}
end

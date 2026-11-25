defmodule PulumiViewer.Inventory do
  @moduledoc """
  The import inventory of the infra repo (`<dir>/<stack>.json`, `components` => items with
  `type`, `name` and an optional `owner` such as `cloudformation:<stack>` or `script:<name>`).
  `PULUMI_VIEWER_INVENTORY` names the folder. A missing folder or file gives an empty map.

  `<dir>/<stack>.options.json` (optional) gives the resource options that the code sets:
  `{"resources": [{"type", "name", "protect", "retainOnDelete", "deleteBeforeReplace"}]}`.
  """

  @doc "{type, name} => item, for the import items of one stack."
  def load(dir, stack) do
    case read(dir, "#{stack}.json") do
      %{"components" => comps} when is_map(comps) ->
        for {_, items} when is_list(items) <- comps,
            %{"type" => t, "name" => n} = it when is_binary(t) and is_binary(n) <- items,
            into: %{},
            do: {{t, n}, it}

      _ ->
        %{}
    end
  end

  @doc "{type, name} => option map, from `<stack>.options.json`."
  def expected(dir, stack) do
    case read(dir, "#{stack}.options.json") do
      %{"resources" => rs} when is_list(rs) ->
        for %{"type" => t, "name" => n} = r <- rs,
            into: %{},
            do: {{t, n}, Map.drop(r, ["type", "name"])}

      _ ->
        %{}
    end
  end

  def owner(inv, r), do: get_in(inv, [Access.key({r.type, r.name}, %{}), "owner"])

  def dir, do: Application.get_env(:pulumi_viewer, :inventory_dir)

  defp read(nil, _), do: nil

  defp read(dir, file) do
    with {:ok, body} <- File.read(Path.join(dir, file)),
         {:ok, doc} <- Jason.decode(body),
         do: doc,
         else: (_ -> nil)
  end
end

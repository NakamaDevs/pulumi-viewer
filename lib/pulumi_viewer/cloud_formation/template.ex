defmodule PulumiViewer.CloudFormation.Template do
  @moduledoc "Parses a CloudFormation template (JSON or YAML) and finds the references between resources."
  alias PulumiViewer.CloudFormation.YamlTags

  def parse(body) when is_binary(body) do
    if String.starts_with?(String.trim_leading(body), "{"),
      do: Jason.decode(body),
      else: yaml(body)
  end

  defp yaml(body) do
    opts = [node_mods: [YamlTags], str_node_as_binary: true, map_node_format: :map]

    case :yamerl_constr.string(String.to_charlist(body), opts) do
      [doc | _] when is_map(doc) -> {:ok, doc}
      _ -> {:error, :not_a_template}
    end
  catch
    {:yamerl_exception, errors} -> {:error, {:yaml, errors}}
  end

  @doc "Logical ID => sorted logical IDs of the resources it references or depends on."
  def dependencies(template) do
    resources = template["Resources"] || %{}
    ids = MapSet.new(Map.keys(resources))

    Map.new(resources, fn {id, res} ->
      deps =
        (refs(res["Properties"]) ++ depends_on(res["DependsOn"]))
        |> Enum.filter(&(MapSet.member?(ids, &1) and &1 != id))
        |> Enum.uniq()
        |> Enum.sort()

      {id, deps}
    end)
  end

  defp depends_on(nil), do: []
  defp depends_on(id) when is_binary(id), do: [id]
  defp depends_on(ids) when is_list(ids), do: Enum.filter(ids, &is_binary/1)
  defp depends_on(_), do: []

  @doc "Logical IDs that a template value references through Ref, Fn::GetAtt or Fn::Sub."
  def refs(%{"Ref" => id}) when is_binary(id), do: [id]
  def refs(%{"Fn::GetAtt" => [id | _]}) when is_binary(id), do: [id]
  def refs(%{"Fn::GetAtt" => s}) when is_binary(s), do: [s |> String.split(".") |> hd()]
  def refs(%{"Fn::Sub" => s}) when is_binary(s), do: sub_refs(s)

  def refs(%{"Fn::Sub" => [s, vars]}) when is_binary(s) and is_map(vars),
    do: (sub_refs(s) -- Map.keys(vars)) ++ refs(vars)

  def refs(m) when is_map(m), do: Enum.flat_map(m, fn {_, v} -> refs(v) end)
  def refs(l) when is_list(l), do: Enum.flat_map(l, &refs/1)
  def refs(_), do: []

  # "${Name}" and "${Name.Attr}"; "${!Literal}" is an escape, not a reference
  defp sub_refs(s) do
    Regex.scan(~r/\$\{([^!}][^}]*)\}/, s, capture: :all_but_first)
    |> Enum.map(fn [ref] -> ref |> String.trim() |> String.split(".") |> hd() end)
  end
end

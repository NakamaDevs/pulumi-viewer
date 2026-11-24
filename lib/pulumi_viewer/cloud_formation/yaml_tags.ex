defmodule PulumiViewer.CloudFormation.YamlTags do
  @moduledoc """
  yamerl node module for the CloudFormation short-form tags (`!Ref`, `!GetAtt`, `!Sub`, ...).

  The tagged node is built by the normal scalar, sequence or mapping module and then
  wrapped in its long form, so `!GetAtt Bucket.Arn` becomes
  `%{"Fn::GetAtt" => ["Bucket", "Arn"]}`.
  """
  require Record

  # Field order of the yamerl records (yamerl_tokens.hrl, internal/yamerl_constr.hrl).
  Record.defrecordp(:unfinished_node, module: nil, path: nil, pres: nil, priv: nil)

  Record.defrecordp(:collection_start, :yamerl_collection_start,
    line: 1,
    column: 1,
    tag: nil,
    style: :block,
    kind: :sequence
  )

  Record.defrecordp(:scalar, :yamerl_scalar,
    line: 1,
    column: 1,
    tag: nil,
    style: :flow,
    substyle: :plain,
    text: ""
  )

  Record.defrecordp(:tag, :yamerl_tag, line: 1, column: 1, uri: "!")

  @functions ~w(Ref Condition GetAtt Sub Join If Select Split FindInMap Base64 Cidr
                ImportValue GetAZs Equals And Or Not Transform Length ToJsonString)

  def tags, do: Enum.map(@functions, &String.to_charlist("!" <> &1))

  def construct_token(constr, :undefined, token) do
    {inner, t} =
      case token do
        collection_start(kind: :sequence, tag: t) -> {:yamerl_node_seq, t}
        collection_start(kind: :mapping, tag: t) -> {:yamerl_node_map, t}
        scalar(tag: t) -> {:yamerl_node_str, t}
      end

    name = t |> tag(:uri) |> to_string() |> String.trim_leading("!")
    rewrap(inner.construct_token(constr, :undefined, token), inner, name)
  end

  def construct_token(constr, unfinished_node(priv: {inner, name, node}), token),
    do: rewrap(inner.construct_token(constr, node, token), inner, name)

  def construct_node(constr, unfinished_node(priv: {inner, name, node}), child),
    do: rewrap(inner.construct_node(constr, node, child), inner, name)

  def node_pres(node), do: unfinished_node(node, :pres)

  defp rewrap({:finished, value}, _inner, name), do: {:finished, long_form(name, value)}

  defp rewrap({:unfinished, node, leaf?}, inner, name) do
    {:unfinished,
     unfinished_node(
       module: __MODULE__,
       path: unfinished_node(node, :path),
       pres: unfinished_node(node, :pres),
       priv: {inner, name, node}
     ), leaf?}
  end

  defp long_form("GetAtt", value) when is_binary(value),
    do: %{"Fn::GetAtt" => String.split(value, ".", parts: 2)}

  defp long_form(name, value) when name in ["Ref", "Condition"], do: %{name => value}
  defp long_form(name, value), do: %{("Fn::" <> name) => value}
end

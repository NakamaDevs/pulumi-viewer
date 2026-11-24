defmodule PulumiViewer.Environment do
  @moduledoc """
  The environment of a stack. Only `dev`, `staging` and `prod` are environments; `shared`,
  `ci` and other stacks are account-wide.

  - Pulumi: the stack name, or `<env>-<anything>`, or `<anything>-<env>`.
  - CloudFormation: the first token of the name that is `dev|prod|staging|shared|ci`;
    otherwise `shared`.
  """

  @envs ~w(dev staging prod)
  @account ~w(shared ci)

  @type t :: {:env, String.t()} | {:account, String.t()}

  def of(:pulumi, name) when name in @envs, do: {:env, name}

  def of(:pulumi, name) do
    tokens = String.split(name, "-")

    cond do
      hd(tokens) in @envs -> {:env, hd(tokens)}
      List.last(tokens) in @envs -> {:env, List.last(tokens)}
      true -> {:account, name}
    end
  end

  def of(:cloudformation, name) do
    case name |> String.split("-") |> Enum.find(&(&1 in @envs or &1 in @account)) do
      nil -> {:account, "shared"}
      t when t in @envs -> {:env, t}
      t -> {:account, t}
    end
  end

  @doc "Environments in dev, staging, prod order (others after), then account-wide groups."
  def sort_key({:env, e}), do: {0, Enum.find_index(@envs, &(&1 == e)) || 99, e}
  def sort_key({:account, a}), do: {1, 0, a}

  def label({:env, e}), do: String.upcase(e)
  def label({:account, a}), do: a
end

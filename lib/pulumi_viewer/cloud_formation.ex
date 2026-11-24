defmodule PulumiViewer.CloudFormation do
  @moduledoc """
  Read-only CloudFormation source: `cloudformation://<region>[?prefix=<stack name prefix>]`.
  It shows each live stack as a stack, grouped by the part of the name before the first `-`.
  """
  alias PulumiViewer.CloudFormation.{Client, Mapping, Template}

  @behaviour PulumiViewer.Storage

  # Not a key-value backend: State calls stacks/1, checkpoint/2 and updates/3 instead.
  @impl true
  def list(_cfg, _prefix), do: []
  @impl true
  def read(_cfg, _key), do: {:error, :not_a_state_backend}

  def parse_url(rest) do
    uri = URI.parse("cloudformation://" <> rest)
    query = URI.decode_query(uri.query || "")
    %{region: uri.host, prefix: blank(query["prefix"])}
  end

  def stacks(%{region: region, prefix: prefix}) do
    with {:ok, summaries} <- Client.list_stacks(region),
         do: {:ok, Mapping.stacks(summaries, prefix)}
  end

  def checkpoint(cfg, stack) do
    with {:ok, stacks} <- stacks(cfg),
         true <- Enum.any?(stacks, &(&1.stack == stack)) || {:error, :not_found},
         {:ok, desc} <- Client.describe_stack(cfg.region, stack),
         {:ok, resources} <- Client.list_stack_resources(cfg.region, stack),
         {:ok, body} <- Client.get_template(cfg.region, stack) do
      template =
        case Template.parse(body) do
          {:ok, t} -> t
          _ -> %{}
        end

      {:ok, Mapping.checkpoint(desc, resources, template)}
    end
  end

  def updates(cfg, stack, limit) do
    case Client.describe_stack_events(cfg.region, stack) do
      {:ok, events} -> events |> Mapping.updates() |> Enum.take(limit)
      _ -> []
    end
  end

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(v), do: v
end

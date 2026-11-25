defmodule PulumiViewer.CloudFormation.Mapping do
  @moduledoc """
  Maps CloudFormation API data to the shapes the viewer already uses for Pulumi:
  stacks, a checkpoint with resources, and update history. Pure functions, no network.
  """
  alias PulumiViewer.CloudFormation.Template

  @stack_type "AWS::CloudFormation::Stack"

  @doc "Project of a stack: the part before the first `-` (`quickbuy-prod-site` -> `quickbuy`)."
  def project(name) do
    case String.split(name, "-", parts: 2) do
      [p, _] when p != "" -> p
      _ -> "cloudformation"
    end
  end

  def live?(%{"StackStatus" => status}), do: status != "DELETE_COMPLETE"

  def stacks(summaries, prefix) do
    summaries
    |> Enum.filter(&live?/1)
    |> Enum.filter(&(prefix in [nil, ""] or String.starts_with?(&1["StackName"], prefix)))
    |> Enum.map(fn s ->
      name = s["StackName"]
      %{project: project(name), stack: name, key: name}
    end)
    |> Enum.uniq_by(& &1.stack)
    |> Enum.sort_by(&{&1.project, &1.stack})
  end

  def stack_urn(name), do: "cfn:" <> name
  def urn(stack, logical_id), do: "cfn:#{stack}::#{logical_id}"

  @doc "A checkpoint like `PulumiViewer.Pulumi.Checkpoint.parse/1` returns."
  def checkpoint(stack, resources, template) do
    name = stack["StackName"]
    deps = Template.dependencies(template)
    tpl = template["Resources"] || %{}

    root = %{
      urn: stack_urn(name),
      name: name,
      type: @stack_type,
      package: "cloudformation",
      module: "Stack",
      id: stack["StackId"],
      custom: false,
      protect: stack["EnableTerminationProtection"] in [true, "true"],
      parent_urn: nil,
      provider_urn: nil,
      dependencies: [],
      inputs: pairs(stack["Parameters"], "ParameterKey", "ParameterValue"),
      outputs: pairs(stack["Outputs"], "OutputKey", "OutputValue")
    }

    children =
      Enum.map(resources, fn r ->
        id = r["LogicalResourceId"]
        {package, module} = split_type(r["ResourceType"])

        %{
          urn: urn(name, id),
          name: id,
          type: r["ResourceType"],
          package: package,
          module: module,
          id: r["PhysicalResourceId"],
          custom: true,
          protect: false,
          parent_urn: nil,
          provider_urn: nil,
          dependencies: Enum.map(Map.get(deps, id, []), &urn(name, &1)),
          inputs: get_in(tpl, [id, "Properties"]) || %{},
          outputs:
            r
            |> Map.take(
              ~w(ResourceStatus ResourceStatusReason LastUpdatedTimestamp DriftInformation)
            )
            |> Map.reject(fn {_, v} -> v in [nil, ""] end)
        }
      end)

    %{
      stack: name,
      updated_at: time(stack["LastUpdatedTime"] || stack["CreationTime"]),
      pulumi_version: stack["StackStatus"],
      resources: [root | children]
    }
  end

  # "AWS::S3::Bucket" -> {"s3", "Bucket"}; "Custom::Thing" -> {"custom", "Thing"}
  defp split_type(type) do
    case String.split(type || "", "::") do
      ["AWS", service | rest] -> {String.downcase(service), Enum.join(rest, "::")}
      [vendor | rest] -> {String.downcase(vendor), Enum.join(rest, "::")}
    end
  end

  defp pairs(list, k, v) when is_list(list), do: Map.new(list, &{&1[k], &1[v]})
  defp pairs(_, _, _), do: %{}

  @start ~r/^(CREATE|UPDATE|DELETE|IMPORT)_IN_PROGRESS$/
  @finish ~r/_(COMPLETE|FAILED)$/
  @done ~r/^(CREATE|UPDATE|DELETE|IMPORT)_COMPLETE$/

  @doc """
  Groups `DescribeStackEvents` output (newest first, as AWS returns it) into updates.
  An update starts at a stack-level `*_IN_PROGRESS` and ends at the next stack-level
  `*_COMPLETE` or `*_FAILED`; a stack-level `*_IN_PROGRESS` before that end is part of the same update. Returns the newest update first.
  """
  def updates(events) do
    events
    |> Enum.reverse()
    |> Enum.reduce([], fn e, groups ->
      status = e["ResourceStatus"] || ""

      cond do
        # CloudFormation logs a stack-level *_IN_PROGRESS again inside one operation (for example
        # "Eventual consistency check initiated"); while an update is open, it continues that update.
        stack_event?(e) and status =~ @start and groups != [] and hd(groups).finish == nil ->
          groups

        stack_event?(e) and status =~ @start ->
          [%{start: e, events: [], finish: nil} | groups]

        groups == [] ->
          groups

        stack_event?(e) and status =~ @finish and hd(groups).finish == nil ->
          [%{hd(groups) | finish: e} | tl(groups)]

        hd(groups).finish == nil and not stack_event?(e) ->
          [%{hd(groups) | events: [e | hd(groups).events]} | tl(groups)]

        true ->
          groups
      end
    end)
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {g, version} -> update(g, version) end)
    |> Enum.reverse()
  end

  defp stack_event?(e),
    do: e["ResourceType"] == @stack_type and e["LogicalResourceId"] == e["StackName"]

  defp update(%{start: start, events: events, finish: finish}, version) do
    started = time(start["Timestamp"])
    ended = finish && time(finish["Timestamp"])
    final = finish && finish["ResourceStatus"]
    failure = events |> Enum.reverse() |> Enum.find(&(&1["ResourceStatus"] =~ "FAILED"))

    resources =
      events
      |> Enum.filter(&(&1["ResourceStatus"] =~ @done))
      |> Enum.map(
        &%{op: op(&1["ResourceStatus"]), name: &1["LogicalResourceId"], type: &1["ResourceType"]}
      )
      |> Enum.uniq()
      |> Enum.sort_by(&{&1.op, &1.name})

    %{
      version: version,
      kind: start["ResourceStatus"] |> String.split("_") |> hd() |> String.downcase(),
      result:
        cond do
          final == nil -> "in-progress"
          final =~ ~r/ROLLBACK|FAILED/ -> "failed"
          true -> "succeeded"
        end,
      message:
        if(failure,
          do: "#{failure["LogicalResourceId"]}: #{failure["ResourceStatusReason"]}",
          else: start["ResourceStatusReason"]
        ),
      started_at: started,
      duration_s: started && ended && DateTime.diff(ended, started),
      changes: Enum.frequencies_by(resources, & &1.op),
      resources: resources
    }
  end

  defp op(status), do: status |> String.split("_") |> hd() |> String.downcase()

  def time(nil), do: nil

  def time(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end

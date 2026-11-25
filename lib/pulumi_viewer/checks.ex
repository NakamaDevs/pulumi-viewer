defmodule PulumiViewer.Checks do
  @moduledoc """
  Safety checks on one Pulumi stack that `pulumi preview` does not give. Read only.

  - `:option_mismatch` - the resource options in state differ from what the code sets. The
    expected options come from `<stack>.options.json` when it has the resource, else from the
    owner rule of the infra repo: a CloudFormation-owned resource must be protected and have
    retainOnDelete; a script-owned resource must not have retainOnDelete.
  - `:double_owner` - the resource is in Pulumi state and a CloudFormation stack owns it. Info
    when it is protected and retained (a Pulumi delete only forgets it), else an error.
  - `:unprotected` - not protected in a stack where most resources are protected.

  State edits (changes outside an update) show in History; see `PulumiViewer.Infra.State`.
  """

  @type finding :: %{
          check: :option_mismatch | :double_owner | :unprotected | :state_edit,
          severity: :error | :warning | :info,
          urn: String.t(),
          name: String.t(),
          type: String.t(),
          message: String.t()
        }

  @options [
    {"protect", :protect},
    {"retainOnDelete", :retain_on_delete},
    {"deleteBeforeReplace", :delete_before_replace}
  ]

  @doc "Who manages the resource: `%{kind: :cloudformation | :other | :pulumi, name: ...}`."
  def owner(r, inventory, links) do
    inv = PulumiViewer.Inventory.owner(inventory, r)
    cfn = Enum.find(Map.get(links, r.id || "", []), &(&1.kind == :cloudformation))

    cond do
      is_binary(inv) and String.starts_with?(inv, "cloudformation:") ->
        %{kind: :cloudformation, name: String.replace_prefix(inv, "cloudformation:", "")}

      # same physical ID only: S3 sub-resources share the bucket ID, so this is a hint, not proof
      cfn ->
        %{kind: :cloudformation, name: cfn.stack, by: :link}

      is_binary(inv) ->
        %{kind: :other, name: inv}

      true ->
        %{kind: :pulumi, name: nil}
    end
  end

  @doc "Findings for the resources of one stack. Options: `:inventory`, `:links`, `:expected`."
  @spec run([map()], keyword()) :: [finding()]
  def run(resources, opts \\ []) do
    inv = Keyword.get(opts, :inventory, %{})
    links = Keyword.get(opts, :links, %{})
    expected = Keyword.get(opts, :expected, %{})
    managed = Enum.reject(resources, &String.starts_with?(&1.type || "", "pulumi:"))
    protect_default? = managed != [] and Enum.count(managed, & &1.protect) * 2 > length(managed)

    Enum.flat_map(managed, fn r ->
      o = owner(r, inv, links)

      mismatch(r, Map.get(expected, {r.type, r.name}) || rule(o)) ++
        double_owner(r, o) ++
        if(protect_default? and not r.protect,
          do: [
            finding(
              :unprotected,
              :warning,
              r,
              "Not protected. Most resources of this stack are protected."
            )
          ],
          else: []
        )
    end)
    |> Enum.sort_by(&{severity_rank(&1.severity), &1.check, &1.name})
  end

  @doc """
  Flags, owner and findings of one Pulumi stack, plus a `:state_edit` finding for each resource
  that changed outside an update. `links` defaults to a fresh CloudFormation link index.
  """
  def for_stack(source, project, stack, links \\ nil, resources \\ nil) do
    alias PulumiViewer.{Infra, Inventory}

    loaded =
      if resources,
        do: {:ok, %{resources: resources}},
        else: Infra.State.checkpoint(source, project, stack)

    with {:ok, cp} <- loaded do
      links = links || Infra.Links.index(:pulumi)
      inv = Inventory.load(Inventory.dir(), stack)
      opts = [inventory: inv, links: links, expected: Inventory.expected(Inventory.dir(), stack)]

      edits =
        case Infra.State.updates(source, project, stack, 1) do
          [%{kind: "state edit", resources: rs} | _] ->
            for c <- rs,
                r =
                  Enum.find(cp.resources, &(&1.name == c.name and &1.type == c.type)) ||
                    %{urn: nil, name: c.name, type: c.type},
                do: finding(:state_edit, :warning, r, "Changed outside an update: #{c.op}.")

          _ ->
            []
        end

      resources =
        Enum.map(cp.resources, fn r ->
          %{
            urn: r.urn,
            name: r.name,
            type: r.type,
            id: r.id,
            protect: r.protect,
            retain_on_delete: r.retain_on_delete,
            delete_before_replace: r.delete_before_replace,
            owner: owner(r, inv, links)
          }
        end)

      {:ok, %{resources: resources, findings: edits ++ run(cp.resources, opts)}}
    end
  end

  defp rule(%{by: :link}), do: nil
  defp rule(%{kind: :cloudformation}), do: %{"protect" => true, "retainOnDelete" => true}
  defp rule(%{kind: :other, name: "script:" <> _}), do: %{"retainOnDelete" => false}
  defp rule(_), do: nil

  defp mismatch(_r, nil), do: []

  defp mismatch(r, want) do
    diffs =
      for {key, field} <- @options,
          Map.has_key?(want, key),
          {w} = {want[key] == true},
          Map.get(r, field, false) != w,
          do: {key, w}

    case diffs do
      [] ->
        []

      _ ->
        sev =
          if Enum.any?(diffs, fn {k, w} -> w and k in ["protect", "retainOnDelete"] end),
            do: :error,
            else: :warning

        text = Enum.map_join(diffs, "; ", fn {k, w} -> "code sets #{k}=#{w}, state has #{!w}" end)
        [finding(:option_mismatch, sev, r, text)]
    end
  end

  defp double_owner(r, %{kind: :cloudformation, name: stack, by: :link}),
    do: [
      finding(
        :double_owner,
        :info,
        r,
        "Same physical ID as a resource of CloudFormation stack #{stack}. Check if the stack owns it."
      )
    ]

  defp double_owner(r, %{kind: :cloudformation, name: stack}) do
    if r.protect and r.retain_on_delete,
      do: [
        finding(
          :double_owner,
          :info,
          r,
          "Also owned by CloudFormation stack #{stack}. Protected and retained."
        )
      ],
      else: [
        finding(
          :double_owner,
          :error,
          r,
          "Also owned by CloudFormation stack #{stack}, but not protected and retained: a Pulumi delete removes it from AWS."
        )
      ]
  end

  defp double_owner(_, _), do: []

  defp finding(check, sev, r, msg),
    do: %{check: check, severity: sev, urn: r.urn, name: r.name, type: r.type, message: msg}

  defp severity_rank(:error), do: 0
  defp severity_rank(:warning), do: 1
  defp severity_rank(_), do: 2
end

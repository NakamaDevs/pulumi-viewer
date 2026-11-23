defmodule PulumiViewer.Pulumi.Checkpoint do
  @moduledoc "Parses a Pulumi stack checkpoint (the format of `pulumi stack export`)."

  @secret_sig "4dabf18193072939515e22adb298388d"

  def parse(<<0x1F, 0x8B, _::binary>> = gz), do: parse(:zlib.gunzip(gz))

  def parse(json) when is_binary(json) do
    with {:ok, doc} <- Jason.decode(json) do
      cp = Map.get(doc, "checkpoint", doc)
      latest = cp["latest"] || %{}
      manifest = latest["manifest"] || %{}

      {:ok,
       %{
         stack: cp["stack"],
         updated_at: parse_time(manifest["time"]),
         pulumi_version: manifest["version"],
         resources: Enum.map(latest["resources"] || [], &resource/1)
       }}
    end
  end

  defp resource(r) do
    type = r["type"] || ""
    {package, module} = split_type(type)

    %{
      urn: r["urn"],
      name: r["urn"] |> to_string() |> String.split("::") |> List.last(),
      type: type,
      package: package,
      module: module,
      id: r["id"],
      custom: r["custom"] == true,
      protect: r["protect"] == true,
      parent_urn: r["parent"],
      provider_urn: provider_urn(r["provider"]),
      dependencies: r["dependencies"] || [],
      inputs: mask(r["inputs"] || %{}),
      outputs: mask(r["outputs"] || %{})
    }
  end

  # "aws:s3/bucketV2:BucketV2" -> {"aws", "s3"}; "pulumi:pulumi:Stack" -> {"pulumi", "pulumi"}
  defp split_type(type) do
    case String.split(type, ":") do
      [pkg, mod | _] -> {pkg, mod |> String.split("/") |> hd()}
      [pkg] -> {pkg, nil}
    end
  end

  # A provider reference is "<provider urn>::<provider id>".
  defp provider_urn(nil), do: nil

  defp provider_urn(ref) do
    parts = String.split(ref, "::")
    parts |> Enum.drop(-1) |> Enum.join("::")
  end

  defp mask(%{@secret_sig => _}), do: "[secret]"
  defp mask(m) when is_map(m), do: Map.new(m, fn {k, v} -> {k, mask(v)} end)
  defp mask(l) when is_list(l), do: Enum.map(l, &mask/1)
  defp mask(v), do: v

  defp parse_time(nil), do: nil

  defp parse_time(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end

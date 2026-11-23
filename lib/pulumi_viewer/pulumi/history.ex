defmodule PulumiViewer.Pulumi.History do
  @moduledoc "Parses one `<stack>-<nanos>.history.json` update record."

  def parse(json) do
    with {:ok, h} <- Jason.decode(json) do
      start = h["startTime"]
      finish = h["endTime"]

      {:ok,
       %{
         kind: h["kind"],
         result: h["result"],
         version: h["version"],
         message: h["message"],
         started_at: start && DateTime.from_unix!(start),
         duration_s: start && finish && finish - start,
         changes: h["resourceChanges"] || %{}
       }}
    end
  end
end

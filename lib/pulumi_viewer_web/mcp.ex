defmodule PulumiViewerWeb.MCP do
  @moduledoc """
  A small read-only MCP server (Streamable HTTP, JSON responses only) at `POST /mcp`.
  Tools: `checks` and `flags`, the same as `PulumiViewer.CLI`.
  """
  import Plug.Conn

  @protocol "2025-06-18"

  @tools [
    %{
      name: "checks",
      description:
        "Safety checks of Pulumi state that pulumi preview does not give: resource options in state that differ from the code (protect, retainOnDelete), resources also owned by CloudFormation, unprotected resources in a protected stack, and state edits outside an update. Read only.",
      inputSchema: %{
        type: "object",
        properties: %{
          source: %{type: "string", description: "Source name; all Pulumi sources when empty"},
          stack: %{type: "string", description: "PROJECT/STACK; all stacks when empty"},
          min: %{
            type: "string",
            enum: ["error", "warning", "info"],
            description: "Lowest severity to list"
          }
        }
      },
      annotations: %{readOnlyHint: true}
    },
    %{
      name: "flags",
      description:
        "protect, retainOnDelete, deleteBeforeReplace and owner of each resource of one stack. Read only.",
      inputSchema: %{
        type: "object",
        properties: %{
          source: %{type: "string"},
          stack: %{type: "string", description: "PROJECT/STACK"}
        },
        required: ["stack"]
      },
      annotations: %{readOnlyHint: true}
    }
  ]

  def init(opts), do: opts

  def call(%{method: "POST"} = conn, _opts) do
    # Plug.Parsers in the endpoint has already decoded a JSON body.
    parsed =
      case conn.body_params do
        %{"method" => _} = p -> {:ok, p}
        _ -> :error
      end

    case parsed do
      {:ok, %{"id" => id, "method" => m} = req} ->
        reply(conn, id, handle(m, req["params"] || %{}))

      {:ok, %{"method" => _}} ->
        send_resp(conn, 202, "")

      _ ->
        reply(conn, nil, {:error, -32700, "parse error"})
    end
  end

  def call(conn, _), do: conn |> put_resp_header("allow", "POST") |> send_resp(405, "")

  defp handle("initialize", _),
    do:
      {:ok,
       %{
         protocolVersion: @protocol,
         capabilities: %{tools: %{}},
         serverInfo: %{
           name: "pulumi-viewer",
           version: to_string(Application.spec(:pulumi_viewer, :vsn))
         }
       }}

  defp handle("ping", _), do: {:ok, %{}}
  defp handle("tools/list", _), do: {:ok, %{tools: @tools}}

  defp handle("tools/call", %{"name" => name} = p) when name in ["checks", "flags"] do
    args = p["arguments"] || %{}

    argv = [
      name
      | for(k <- ~w(source stack min), v = args[k], v not in [nil, ""], do: ["--#{k}", v])
        |> List.flatten()
    ]

    {code, out} = PulumiViewer.CLI.run(argv)

    {:ok,
     %{
       content: [%{type: "text", text: Jason.encode!(out)}],
       structuredContent: out,
       isError: code == 2
     }}
  end

  defp handle("tools/call", _), do: {:error, -32602, "unknown tool"}
  defp handle(_, _), do: {:error, -32601, "method not found"}

  defp reply(conn, id, {:ok, result}), do: json(conn, %{jsonrpc: "2.0", id: id, result: result})

  defp reply(conn, id, {:error, code, msg}),
    do: json(conn, %{jsonrpc: "2.0", id: id, error: %{code: code, message: msg}})

  defp json(conn, map),
    do: conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(map))
end

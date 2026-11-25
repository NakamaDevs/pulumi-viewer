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

  def call(%{method: "POST"} = conn, opts) do
    cond do
      not json?(conn) -> send_resp(conn, 415, "")
      not origin_ok?(conn) -> send_resp(conn, 403, "")
      true -> rpc(conn, opts)
    end
  end

  def call(conn, _), do: conn |> put_resp_header("allow", "POST") |> send_resp(405, "")

  # A cross-site HTML form can post urlencoded bodies without a preflight.
  defp json?(conn),
    do:
      Enum.any?(
        get_req_header(conn, "content-type"),
        &String.starts_with?(String.downcase(&1), "application/json")
      )

  # DNS rebinding guard (MCP Streamable HTTP): a browser Origin must be this host or a local one.
  defp origin_ok?(conn) do
    case get_req_header(conn, "origin") do
      [] ->
        true

      [origin | _] ->
        host = URI.parse(origin).host || ""

        # never conn.host: under DNS rebinding the Host header is the attacker's name too
        configured = PulumiViewerWeb.Endpoint.config(:url)[:host]

        host in [configured, "localhost", "127.0.0.1"] or String.ends_with?(host, ".localhost")
    end
  end

  defp rpc(conn, _opts) do
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
    case p["arguments"] || %{} do
      %{} = args ->
        if Enum.all?(~w(source stack min), &(args[&1] == nil or is_binary(args[&1]))),
          do: call_tool(name, args),
          else: {:error, -32602, "source, stack and min must be strings"}

      _ ->
        {:error, -32602, "arguments must be an object"}
    end
  end

  defp handle("tools/call", _), do: {:error, -32602, "unknown tool"}
  defp handle(_, _), do: {:error, -32601, "method not found"}

  defp call_tool(name, args) do
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
       isError: code == 2 or (name == "flags" and code != 0)
     }}
  end

  defp reply(conn, id, {:ok, result}), do: json(conn, %{jsonrpc: "2.0", id: id, result: result})

  defp reply(conn, id, {:error, code, msg}),
    do: json(conn, %{jsonrpc: "2.0", id: id, error: %{code: code, message: msg}})

  defp json(conn, map),
    do: conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(map))
end

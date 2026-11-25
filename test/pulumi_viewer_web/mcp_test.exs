defmodule PulumiViewerWeb.MCPTest do
  use PulumiViewerWeb.ConnCase, async: false

  setup do
    Application.put_env(:pulumi_viewer, :sources, "guarded=file://test/fixtures/guarded")
    Application.put_env(:pulumi_viewer, :inventory_dir, "test/fixtures/guarded/inventory")

    on_exit(fn ->
      Application.delete_env(:pulumi_viewer, :sources)
      Application.delete_env(:pulumi_viewer, :inventory_dir)
    end)
  end

  defp rpc(conn, method, params \\ %{}) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: method, params: params}))
    |> json_response(200)
  end

  test "initialize and tools/list", %{conn: conn} do
    assert %{"result" => %{"capabilities" => %{"tools" => _}}} = rpc(conn, "initialize")
    names = rpc(build_conn(), "tools/list")["result"]["tools"] |> Enum.map(& &1["name"])
    assert names == ["checks", "flags"]
  end

  test "tools/call checks returns the findings", %{conn: conn} do
    res =
      rpc(conn, "tools/call", %{name: "checks", arguments: %{stack: "bundle/prod", min: "error"}})[
        "result"
      ]

    [st] = res["structuredContent"]["stacks"]
    assert Enum.map(st["findings"], & &1["name"]) |> Enum.sort() == ["logs", "logs"]
    refute res["isError"]
  end

  test "a notification gets 202 and GET gets 405", %{conn: conn} do
    c =
      conn
      |> put_req_header("content-type", "application/json")
      |> post("/mcp", ~s({"jsonrpc":"2.0","method":"notifications/initialized"}))

    assert c.status == 202
    assert get(build_conn(), "/mcp").status == 405
  end
end

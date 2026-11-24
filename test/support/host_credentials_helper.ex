defmodule PulumiViewer.HostCredentialsHelper do
  @moduledoc """
  A local stub of the host credential helper (ECS JSON format) that rotates keys on each call.

  `/creds` answers as the helper. Any other path answers as S3 with the body `state-body` and
  keeps the request's `authorization` header in `:persistent_term` under `{__MODULE__, :s3_auth}`.
  """
  @behaviour Plug

  def init(o), do: o

  def call(%Plug.Conn{request_path: "/creds"} = conn, _) do
    case :persistent_term.get({__MODULE__, :mode}) do
      :down ->
        Plug.Conn.send_resp(conn, 500, "no session")

      :up ->
        "token-1" = conn |> Plug.Conn.get_req_header("authorization") |> List.first()
        c = :persistent_term.get(__MODULE__)
        :counters.add(c, 1, 1)
        n = :counters.get(c, 1)
        ttl = :persistent_term.get({__MODULE__, :ttl})

        body =
          Jason.encode!(%{
            "AccessKeyId" => "ASIA#{n}",
            "SecretAccessKey" => "secret#{n}",
            "Token" => "token#{n}",
            "Expiration" =>
              DateTime.utc_now() |> DateTime.add(ttl, :millisecond) |> DateTime.to_iso8601()
          })

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, body)
    end
  end

  def call(conn, _) do
    auth = conn |> Plug.Conn.get_req_header("authorization") |> List.first()
    :persistent_term.put({__MODULE__, :s3_auth}, auth)
    Plug.Conn.send_resp(conn, 200, "state-body")
  end

  @doc "How many times the helper gave keys."
  def calls, do: :counters.get(:persistent_term.get(__MODULE__), 1)
end

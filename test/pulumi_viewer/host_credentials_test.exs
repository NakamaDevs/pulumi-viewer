defmodule PulumiViewer.HostCredentialsTest do
  # A local stub of the host credential helper (ECS JSON format) that rotates keys on each call.
  use ExUnit.Case, async: false
  alias PulumiViewer.HostCredentials

  defmodule Helper do
    @behaviour Plug
    def init(o), do: o

    def call(conn, _) do
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
  end

  @vars ~w(AWS_CONTAINER_CREDENTIALS_FULL_URI AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE)

  setup do
    :persistent_term.put(Helper, :counters.new(1, []))
    :persistent_term.put({Helper, :mode}, :up)
    pid = start_supervised!({Bandit, plug: Helper, port: 0, ip: :loopback})
    {:ok, {_, port}} = ThousandIsland.listener_info(pid)
    dir = Path.join(System.tmp_dir!(), "pv-host-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "token"), "token-1\n")
    saved = Map.new(@vars, &{&1, System.get_env(&1)})
    System.put_env("AWS_CONTAINER_CREDENTIALS_FULL_URI", "http://127.0.0.1:#{port}/creds")
    System.put_env("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE", Path.join(dir, "token"))
    HostCredentials.clear()

    on_exit(fn ->
      HostCredentials.clear()

      Enum.each(saved, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)

      File.rm_rf!(dir)
    end)
  end

  test "reuses the keys inside the TTL and gets new keys after it" do
    # valid for 1 s past the 60 s refresh lead time
    :persistent_term.put({Helper, :ttl}, 61_000)
    assert {:ok, first} = HostCredentials.fetch()
    assert first[:access_key_id] == "ASIA1"
    assert first[:security_token] == "token1"
    assert {:ok, ^first} = HostCredentials.fetch()

    Process.sleep(1_500)
    assert {:ok, second} = HostCredentials.fetch()
    assert second[:access_key_id] != first[:access_key_id]
  end

  test "a helper that does not answer gives an error, many times, and crashes nothing" do
    :persistent_term.put({Helper, :mode}, :down)
    ex_aws = Process.whereis(ExAws.Supervisor)

    for _ <- 1..6, do: assert({:error, :credential_helper} = HostCredentials.fetch())

    assert Process.whereis(ExAws.Supervisor) == ex_aws
    assert Process.alive?(ex_aws)

    # the helper comes back: the next call works
    :persistent_term.put({Helper, :mode}, :up)
    :persistent_term.put({Helper, :ttl}, 3_600_000)

    assert {:ok, %{access_key_id: "ASIA" <> _}} =
             Map.new(elem(HostCredentials.fetch(), 1)) |> then(&{:ok, &1})
  end

  test "CloudFormation shows the helper hint when the helper is down" do
    :persistent_term.put({Helper, :mode}, :down)
    PulumiViewer.CloudFormation.Cache.clear()

    assert {:error, %PulumiViewer.CloudFormation.Error{message: msg}} =
             PulumiViewer.CloudFormation.Client.list_stacks(%{region: "us-east-1"})

    assert msg =~ "The host credential helper did not answer"
  end
end

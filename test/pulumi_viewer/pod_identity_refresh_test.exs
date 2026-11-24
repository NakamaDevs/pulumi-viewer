defmodule PulumiViewer.PodIdentityRefreshTest do
  # A local stub of the host credential helper (ECS JSON format) that rotates keys on each call.
  use ExUnit.Case, async: false

  defmodule Helper do
    @behaviour Plug
    def init(o), do: o

    def call(conn, _) do
      "token-1" = conn |> Plug.Conn.get_req_header("authorization") |> List.first()
      n = :counters.get(:persistent_term.get(__MODULE__), 1) + 1
      :counters.put(:persistent_term.get(__MODULE__), 1, n)
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

  @vars ~w(AWS_CONTAINER_CREDENTIALS_FULL_URI AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE)
  # config/config.exs sets the ExAws refresh lead time to this value
  @lead_ms 60_000

  setup do
    :persistent_term.put(Helper, :counters.new(1, []))
    pid = start_supervised!({Bandit, plug: Helper, port: 0, ip: :loopback})
    {:ok, {_, port}} = ThousandIsland.listener_info(pid)
    dir = Path.join(System.tmp_dir!(), "pv-pod-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "token"), "token-1\n")
    saved = Map.new(@vars, &{&1, System.get_env(&1)})
    System.put_env("AWS_CONTAINER_CREDENTIALS_FULL_URI", "http://127.0.0.1:#{port}/creds")
    System.put_env("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE", Path.join(dir, "token"))
    reset_auth_cache()

    on_exit(fn ->
      reset_auth_cache()

      Enum.each(saved, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)

      File.rm_rf!(dir)
    end)
  end

  # The cache table is protected: restart ExAws's AuthCache (its supervisor starts a clean one).
  defp reset_auth_cache do
    old = Process.whereis(ExAws.Config.AuthCache)
    Process.exit(old, :kill)
    wait_new(old, 50)
  end

  defp wait_new(_old, 0), do: flunk("ExAws AuthCache did not restart")

  defp wait_new(old, n) do
    case Process.whereis(ExAws.Config.AuthCache) do
      pid when is_pid(pid) and pid != old -> :ok
      _ -> Process.sleep(20) && wait_new(old, n - 1)
    end
  end

  defp keys do
    ExAws.Config.new(:cloudformation,
      access_key_id: [:pod_identity],
      secret_access_key: [:pod_identity],
      security_token: [:pod_identity]
    )
    |> Map.take([:access_key_id, :security_token])
  end

  test "ExAws reuses the credentials inside the TTL and gets new keys after it" do
    # valid for 1 s past the lead time: ExAws refreshes before Expiration
    :persistent_term.put({Helper, :ttl}, @lead_ms + 1_000)
    first = keys()
    assert %{access_key_id: "ASIA" <> _, security_token: "token" <> _} = first
    assert keys() == first

    Process.sleep(1_500)
    second = keys()
    assert first.access_key_id != second.access_key_id
    assert String.starts_with?(second.access_key_id, "ASIA")

    # the helper stops answering: CloudFormation shows the hint instead of crashing
    Process.sleep(1_100)
    System.put_env("AWS_CONTAINER_CREDENTIALS_FULL_URI", "http://127.0.0.1:1/creds")

    Application.put_env(:pulumi_viewer, :cloudformation_aws_opts,
      access_key_id: [:pod_identity],
      secret_access_key: [:pod_identity],
      security_token: [:pod_identity]
    )

    PulumiViewer.CloudFormation.Cache.clear()

    try do
      assert {:error, %PulumiViewer.CloudFormation.Error{message: msg}} =
               PulumiViewer.CloudFormation.Client.list_stacks("us-east-1")

      assert msg =~ "The host credential helper did not answer"
    after
      Application.delete_env(:pulumi_viewer, :cloudformation_aws_opts)
    end
  end
end

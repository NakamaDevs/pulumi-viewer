defmodule PulumiViewer.HostCredentialsTest do
  # A local stub of the host credential helper (ECS JSON format) that rotates keys on each call.
  use ExUnit.Case, async: false
  alias PulumiViewer.HostCredentials
  alias PulumiViewer.HostCredentialsHelper, as: Helper

  @vars ~w(AWS_CONTAINER_CREDENTIALS_FULL_URI AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE
           AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
           AWS_ENDPOINT_URL AWS_ENDPOINT_URL_S3)

  setup do
    :persistent_term.put(Helper, :counters.new(1, []))
    :persistent_term.put({Helper, :mode}, :up)
    :persistent_term.put({Helper, :s3_auth}, nil)
    pid = start_supervised!({Bandit, plug: Helper, port: 0, ip: :loopback})
    {:ok, {_, port}} = ThousandIsland.listener_info(pid)
    dir = Path.join(System.tmp_dir!(), "pv-host-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "token"), "token-1\n")
    saved = Map.new(@vars, &{&1, System.get_env(&1)})
    Enum.each(~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN), &System.delete_env/1)
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

    %{port: port}
  end

  test "reuses the keys inside the TTL and gets new keys after it" do
    :persistent_term.put({Helper, :ttl}, 3_600_000)
    assert {:ok, first} = HostCredentials.fetch()
    assert first[:access_key_id] == "ASIA1"
    assert first[:security_token] == "token1"
    assert {:ok, ^first} = HostCredentials.fetch()
    assert Helper.calls() == 1

    # inside the 60 s refresh lead time: new keys
    :ets.insert(HostCredentials, {:keys, first, System.os_time(:second) + 59})
    assert {:ok, second} = HostCredentials.fetch()
    assert second[:access_key_id] == "ASIA2"

    # expired: new keys
    :ets.insert(HostCredentials, {:keys, second, System.os_time(:second) - 1})
    assert {:ok, third} = HostCredentials.fetch()
    assert third[:access_key_id] == "ASIA3"
  end

  test "a helper that does not answer gives an error, many times, and crashes nothing" do
    :persistent_term.put({Helper, :mode}, :down)
    ex_aws = Process.whereis(ExAws.Supervisor)
    ref = Process.monitor(ex_aws)

    for _ <- 1..6, do: assert({:error, :credential_helper} = HostCredentials.fetch())

    assert Process.whereis(ExAws.Supervisor) == ex_aws
    refute_received {:DOWN, ^ref, :process, _, _}

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

  describe "S3 without a profile" do
    setup %{port: port} do
      System.put_env("AWS_ENDPOINT_URL_S3", "http://127.0.0.1:#{port}")
      :persistent_term.put({Helper, :ttl}, 3_600_000)
      :ok
    end

    test "uses the host helper when no keys are in the environment" do
      assert {:ok, "state-body"} = PulumiViewer.Storage.S3.read(%{bucket: "b", prefix: nil}, "k")
      assert Helper.calls() == 1
      assert :persistent_term.get({Helper, :s3_auth}) =~ "Credential=ASIA1/"
    end

    test "keys in the environment win over the host helper, as for CloudFormation" do
      :persistent_term.put({Helper, :mode}, :down)
      System.put_env("AWS_ACCESS_KEY_ID", "AKIAENV")
      System.put_env("AWS_SECRET_ACCESS_KEY", "env-secret")
      System.put_env("AWS_SESSION_TOKEN", "env-token")

      assert {:ok, "state-body"} = PulumiViewer.Storage.S3.read(%{bucket: "b", prefix: nil}, "k")
      assert Helper.calls() == 0
      assert :persistent_term.get({Helper, :s3_auth}) =~ "Credential=AKIAENV/"
    end
  end
end

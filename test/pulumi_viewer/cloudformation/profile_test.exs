defmodule PulumiViewer.CloudFormation.ProfileTest do
  # Changes PATH and AWS variables, so it does not run async.
  use ExUnit.Case, async: false

  alias PulumiViewer.AwsCredentials
  alias PulumiViewer.CloudFormation.{Cache, Client}

  @vars ~w(PATH AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE)

  setup do
    saved = Map.new(@vars, &{&1, System.get_env(&1)})
    dir = Path.join(System.tmp_dir!(), "fake-aws-cfn-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    System.put_env("PATH", dir <> ":" <> saved["PATH"])

    Application.put_env(:pulumi_viewer, :cloudformation_aws_opts,
      http_client: PulumiViewer.CfnMock
    )

    :persistent_term.put({PulumiViewer.CfnMock, :report_to}, self())
    AwsCredentials.clear()
    Cache.clear()

    on_exit(fn ->
      Enum.each(saved, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)

      File.rm_rf!(dir)
      Application.delete_env(:pulumi_viewer, :cloudformation_aws_opts)
      :persistent_term.erase({PulumiViewer.CfnMock, :report_to})
      :persistent_term.put({PulumiViewer.CfnMock, :mode}, :ok)
      AwsCredentials.clear()
      Cache.clear()
    end)

    %{dir: dir}
  end

  # The fake `aws configure export-credentials --profile <p>` answers with the key `KEY-<p>`.
  defp fake_aws(dir, script) do
    file = Path.join(dir, "aws")
    File.write!(file, "#!/bin/sh\n" <> script)
    File.chmod!(file, 0o755)
  end

  defp per_profile_keys(dir) do
    fake_aws(
      dir,
      ~s(echo "{\\"AccessKeyId\\":\\"KEY-$4\\",\\"SecretAccessKey\\":\\"s\\",\\"Expiration\\":\\"2099-01-01T00:00:00Z\\"}")
    )
  end

  defp src(name, profile), do: %{name: name, region: "us-east-1", prefix: nil, profile: profile}

  test "a profile source uses only its profile, not the keys in the environment", %{dir: dir} do
    per_profile_keys(dir)
    System.put_env("AWS_ACCESS_KEY_ID", "ENV-KEY")
    System.put_env("AWS_SECRET_ACCESS_KEY", "env-secret")

    assert {:ok, [_ | _]} = Client.list_stacks(src("dev", "dev-p"))
    assert_received {:cfn_key, "KEY-dev-p", "ListStacks"}
    refute_received {:cfn_key, "ENV-KEY", _}
  end

  test "a failing profile fails the source and does not fall back to the environment keys", %{
    dir: dir
  } do
    fake_aws(dir, "echo 'Your session has expired.' >&2; exit 255")
    System.put_env("AWS_ACCESS_KEY_ID", "ENV-KEY")
    System.put_env("AWS_SECRET_ACCESS_KEY", "env-secret")

    assert {:error, e} = Client.list_stacks(src("dev", "dev-p"))
    assert e.source?
    assert e.message =~ "aws login --profile dev-p"
    refute_received {:cfn_key, _, _}
  end

  test "an expired profile source gets its own login hint, not the global AWS_PROFILE", %{
    dir: dir
  } do
    per_profile_keys(dir)
    System.put_env("AWS_PROFILE", "global-profile")
    :persistent_term.put({PulumiViewer.CfnMock, :mode}, :expired)

    assert {:error, e} = Client.list_stacks(src("prod", "prod-p"))
    assert e.source?
    assert e.message =~ "AWS credentials are expired"

    assert e.message =~
             "Run `aws login --profile prod-p` (or `aws sso login --profile prod-p`), then press Refresh."

    refute e.message =~ "global-profile"
  end

  test "two sources in one region with different profiles get separate cache entries", %{
    dir: dir
  } do
    per_profile_keys(dir)

    assert {:ok, [_ | _]} = Client.list_stacks(src("dev", "dev-p"))
    assert {:ok, [_ | _]} = Client.list_stacks(src("prod", "prod-p"))
    assert_received {:cfn_key, "KEY-dev-p", "ListStacks"}
    assert_received {:cfn_key, "KEY-prod-p", "ListStacks"}

    # same name and region, other profile: still its own entry
    assert {:ok, [_ | _]} = Client.list_stacks(src("dev", "other-p"))
    assert_received {:cfn_key, "KEY-other-p", "ListStacks"}

    # a repeated call is served from the cache
    assert {:ok, [_ | _]} = Client.list_stacks(src("dev", "dev-p"))
    refute_received {:cfn_key, _, _}
  end
end

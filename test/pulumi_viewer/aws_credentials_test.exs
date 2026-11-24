defmodule PulumiViewer.AwsCredentialsTest do
  use ExUnit.Case, async: false
  alias PulumiViewer.AwsCredentials

  setup do
    dir = Path.join(System.tmp_dir!(), "fake-aws-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = System.get_env("PATH")
    System.put_env("PATH", dir <> ":" <> path)
    AwsCredentials.clear()

    on_exit(fn ->
      System.put_env("PATH", path)
      File.rm_rf!(dir)
      AwsCredentials.clear()
    end)

    %{dir: dir}
  end

  defp fake_aws(dir, script) do
    file = Path.join(dir, "aws")
    File.write!(file, "#!/bin/sh\n" <> script)
    File.chmod!(file, 0o755)
  end

  test "a profile is resolved with the aws CLI (any profile type, also aws login)", %{dir: dir} do
    fake_aws(
      dir,
      ~s(echo '{"Version":1,"AccessKeyId":"AKIA1","SecretAccessKey":"s","SessionToken":"t","Expiration":"2099-01-01T00:00:00Z"}')
    )

    assert {:ok, opts} = AwsCredentials.opts("dev")
    assert opts[:access_key_id] == "AKIA1"
    assert opts[:security_token] == "t"
  end

  test "an expired aws login shows what to run", %{dir: dir} do
    fake_aws(dir, "echo 'Your session has expired. Please reauthenticate.' >&2; exit 255")
    assert {:error, e} = AwsCredentials.opts("prod")
    assert e.message =~ "prod"
    assert e.message =~ "aws login --profile prod"
  end

  test "no profile uses the keys in the environment" do
    assert {:ok, opts} = AwsCredentials.opts(nil)
    assert is_list(opts)
  end
end

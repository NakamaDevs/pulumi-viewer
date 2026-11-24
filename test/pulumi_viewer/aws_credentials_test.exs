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

  test "a warning on stderr does not break the credentials", %{dir: dir} do
    fake_aws(
      dir,
      ~s(echo 'warning: new version' >&2; echo '{"AccessKeyId":"AKIA2","SecretAccessKey":"s"}')
    )

    assert {:ok, opts} = AwsCredentials.opts("dev")
    assert opts[:access_key_id] == "AKIA2"
  end

  test "an S3 source with a failing profile shows the profile error, not other keys", %{dir: dir} do
    fake_aws(dir, "echo 'expired' >&2; exit 255")
    System.put_env("AWS_ACCESS_KEY_ID", "other-account")
    on_exit(fn -> System.delete_env("AWS_ACCESS_KEY_ID") end)

    e =
      assert_raise PulumiViewer.CloudFormation.Error, fn ->
        PulumiViewer.Storage.S3.list(%{bucket: "b", prefix: nil, profile: "prod"}, ".pulumi/")
      end

    assert e.message =~ "aws login --profile prod"
  end

  test "a profile that hangs times out and its aws process is stopped", %{dir: dir} do
    pidfile = Path.join(dir, "pid")
    fake_aws(dir, "echo $$ > #{pidfile}; exec sleep 30")
    Application.put_env(:pulumi_viewer, :aws_cli_timeout_ms, 500)
    on_exit(fn -> Application.delete_env(:pulumi_viewer, :aws_cli_timeout_ms) end)

    assert {:error, e} = AwsCredentials.opts("mfa")
    assert e.message =~ "did not answer"
    pid = pidfile |> File.read!() |> String.trim()
    assert gone?(pid, 50)
  end

  # `kill -9` is sent before the timeout returns; the OS can take a moment to remove the process.
  # Poll `kill -0` (exit 1: no such process) a bounded number of times instead of one fixed sleep.
  defp gone?(_pid, 0), do: false

  defp gone?(pid, tries) do
    case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
      {_, 1} ->
        true

      _ ->
        Process.sleep(20)
        gone?(pid, tries - 1)
    end
  end

  test "no profile uses the keys in the environment" do
    assert {:ok, opts} = AwsCredentials.opts(nil)
    assert is_list(opts)
  end
end

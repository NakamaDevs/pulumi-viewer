defmodule PulumiViewer.CloudFormation.CredentialSourceTest do
  # Changes process environment variables, so it does not run async.
  use ExUnit.Case, async: false

  alias PulumiViewer.CloudFormation.Client

  @vars ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
           AWS_CONTAINER_CREDENTIALS_RELATIVE_URI AWS_CONTAINER_CREDENTIALS_FULL_URI)

  setup do
    saved = Map.new(@vars, &{&1, System.get_env(&1)})
    Enum.each(@vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(saved, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)
    end)
  end

  test "no credentials at all" do
    assert Client.credential_source() == :none
  end

  test "keys in the environment win over a profile" do
    System.put_env("AWS_ACCESS_KEY_ID", "AKIA")
    System.put_env("AWS_PROFILE", "readonly")
    assert Client.credential_source() == :env
  end

  test "an AWS profile (also SSO) from the shared config, refreshed by ExAws" do
    System.put_env("AWS_PROFILE", "bundle-readonly")
    assert Client.credential_source() == {:profile, "bundle-readonly"}
  end

  test "an ECS container role" do
    System.put_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "/v2/credentials/x")
    assert Client.credential_source() == :container
  end

  test "configparser_ex is available, so ExAws can read ~/.aws/config" do
    assert Code.ensure_loaded?(ConfigParser)
  end
end

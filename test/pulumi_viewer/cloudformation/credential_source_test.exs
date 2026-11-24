defmodule PulumiViewer.CloudFormation.CredentialSourceTest do
  # Changes process environment variables, so it does not run async.
  use ExUnit.Case, async: false

  alias PulumiViewer.CloudFormation.Client

  @vars ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE
           AWS_CONTAINER_CREDENTIALS_RELATIVE_URI AWS_CONTAINER_CREDENTIALS_FULL_URI
           AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE)

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

  test "a host credential helper (full URI and token file) refreshes credentials" do
    System.put_env("AWS_PROFILE", "bundle-readonly")
    System.put_env("AWS_CONTAINER_CREDENTIALS_FULL_URI", "http://host.docker.internal:9911/creds")
    System.put_env("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE", "/run/token")
    assert Client.credential_source() == :container_full_uri
  end

  test "the hint for the host credential helper" do
    assert PulumiViewer.CloudFormation.Error.credentials_hint(:container_full_uri) =~
             "The host credential helper did not answer. Run `aws login --profile bundle-readonly` on the host."
  end

  test "runtime.exs chain: env keys, then the helper, then AWS_PROFILE, then the instance role" do
    System.put_env("AWS_PROFILE", "p")
    System.put_env("AWS_CONTAINER_CREDENTIALS_FULL_URI", "http://h/creds")
    System.put_env("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE", "/run/token")
    ex_aws = Config.Reader.read!("config/runtime.exs", env: :test)[:ex_aws]

    assert ex_aws[:access_key_id] ==
             [{:system, "AWS_ACCESS_KEY_ID"}, :pod_identity, {:awscli, "p", 30}, :instance_role]

    System.delete_env("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE")
    ex_aws = Config.Reader.read!("config/runtime.exs", env: :test)[:ex_aws]
    refute :pod_identity in ex_aws[:security_token]
  end

  test "ExAws refreshes 60 s before Expiration (aws login credentials can be short)" do
    assert Application.get_env(:ex_aws, :auth_refresh_lead_time) == 60_000
  end

  test "configparser_ex is available, so ExAws can read ~/.aws/config" do
    assert Code.ensure_loaded?(ConfigParser)
  end
end

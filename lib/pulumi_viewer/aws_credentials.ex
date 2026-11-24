defmodule PulumiViewer.AwsCredentials do
  @moduledoc """
  ExAws credential options for one source.

  - A source with `?profile=<name>` uses that AWS profile. When the `aws` CLI is installed,
    the viewer runs `aws configure export-credentials`, which reads every profile type
    (keys, SSO, `aws login`, assumed roles). The result is cached until 5 minutes before it
    expires. Without the CLI (for example in the Docker image), ExAws reads the profile from
    `~/.aws` itself (keys and SSO only).
  - A source without a profile uses the keys in the environment, or an ECS task role.
  """

  alias PulumiViewer.CloudFormation.Error

  @keys [:access_key_id, :secret_access_key, :security_token]
  @margin_s 300

  @spec opts(String.t() | nil) :: {:ok, keyword} | {:error, Exception.t()}
  def opts(nil), do: {:ok, env()}

  def opts(profile) do
    case System.find_executable("aws") do
      nil -> {:ok, for(k <- @keys, do: {k, [{:awscli, profile, 30}]})}
      aws -> cached(profile, fn -> export(aws, profile) end)
    end
  end

  @doc "True when there is something to sign a request with."
  def available?(nil, extra) do
    extra[:access_key_id] != nil or env() != [] or
      System.get_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI") != nil or
      System.get_env("AWS_CONTAINER_CREDENTIALS_FULL_URI") != nil
  end

  def available?(_profile, _extra), do: true

  def clear do
    for {{__MODULE__, _} = k, _} <- :persistent_term.get(), do: :persistent_term.erase(k)
    :ok
  end

  defp cached(profile, fun) do
    now = System.system_time(:second)

    case :persistent_term.get({__MODULE__, profile}, nil) do
      {opts, expires} when expires - @margin_s > now ->
        {:ok, opts}

      _ ->
        with {:ok, opts, expires} <- fun.() do
          :persistent_term.put({__MODULE__, profile}, {opts, expires})
          {:ok, opts}
        end
    end
  end

  defp export(aws, profile) do
    args = ["configure", "export-credentials", "--profile", profile, "--format", "process"]

    case System.cmd(aws, args, stderr_to_stdout: true) do
      {out, 0} ->
        case Jason.decode(out) do
          {:ok, %{"AccessKeyId" => key, "SecretAccessKey" => secret} = c} ->
            opts = [
              access_key_id: key,
              secret_access_key: secret,
              security_token: c["SessionToken"]
            ]

            {:ok, opts, expires(c["Expiration"])}

          _ ->
            {:error, profile_error(profile, "the aws CLI returned no credentials")}
        end

      {out, _} ->
        {:error,
         profile_error(profile, out |> String.trim() |> String.split("\n") |> List.last())}
    end
  end

  # keys without an expiration are long-lived; read them again after an hour anyway
  defp expires(nil), do: System.system_time(:second) + 3600

  defp expires(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> System.system_time(:second) + 3600
    end
  end

  defp profile_error(profile, why) do
    %Error{
      code: "ProfileCredentials",
      message:
        "AWS profile #{profile} has no valid credentials (#{why}). " <>
          "Run `aws login --profile #{profile}` (or `aws sso login --profile #{profile}`), then press Refresh."
    }
  end

  # Keys from the environment, without the instance-role fallback for a missing session token.
  defp env do
    case System.get_env("AWS_ACCESS_KEY_ID") do
      k when k in [nil, ""] ->
        []

      key ->
        [
          access_key_id: key,
          secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
          security_token: System.get_env("AWS_SESSION_TOKEN")
        ]
    end
  end
end

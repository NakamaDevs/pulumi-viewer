defmodule PulumiViewer.CloudFormation.Error do
  @moduledoc "A CloudFormation read failed. The message is written for the person who runs the viewer."
  defexception [:message, :code, source?: false]

  @doc """
  The error for a failed read. `profile` is the source's own `?profile=`: when set, every
  credentials hint names that profile, not the global `AWS_PROFILE`.
  """
  def from(error, profile \\ nil)
  def from({:http_error, status, %{body: body}}, p), do: from_body(status, body, p)
  def from({:http_error, status, body}, p) when is_binary(body), do: from_body(status, body, p)
  def from(:no_credentials, p), do: credentials("AWS credentials are missing.", nil, p)
  def from(:credential_helper, p), do: credentials("AWS credentials are missing.", nil, p)

  # ExAws raised or exited. With a profile this is almost always an expired session (ExAws's
  # AuthCache returns nil and ExAws then raises), so keep the login hint.
  def from({:raised, msg}, p) when is_binary(p),
    do: credentials("AWS credentials could not be read (#{msg}).", nil, p)

  def from({:raised, msg}, nil) do
    case PulumiViewer.CloudFormation.Client.credential_source() do
      {:profile, _} -> credentials("AWS credentials could not be read (#{msg}).", nil, nil)
      _ -> %__MODULE__{message: "CloudFormation read failed: #{msg}"}
    end
  end

  def from(%__MODULE__{} = e, _p), do: e
  def from(other, _p), do: %__MODULE__{message: "CloudFormation read failed: #{inspect(other)}"}

  defp from_body(status, body, p) do
    code = xml_value(body, "Code")
    text = xml_value(body, "Message")

    case code do
      c when c in ["ExpiredToken", "ExpiredTokenException", "RequestExpired"] ->
        credentials("AWS credentials are expired.", c, p)

      c
      when c in [
             "InvalidClientTokenId",
             "UnrecognizedClientException",
             "SignatureDoesNotMatch",
             "MissingAuthenticationToken"
           ] ->
        credentials("AWS credentials are not valid.", c, p)

      "AccessDenied" <> _ ->
        %__MODULE__{
          code: code,
          message:
            "Access denied: #{text}. The viewer needs cloudformation:ListStacks, DescribeStacks, ListStackResources, DescribeStackEvents and GetTemplate."
        }

      _ ->
        %__MODULE__{
          code: code,
          message: "CloudFormation returned HTTP #{status}: #{code} #{text}"
        }
    end
  end

  defp credentials(what, code, profile) do
    hint =
      cond do
        is_binary(profile) ->
          profile_hint(profile)

        PulumiViewer.CloudFormation.Client.credential_source() == :container_full_uri ->
          credentials_hint(:container_full_uri)

        true ->
          credentials_hint(System.get_env("AWS_PROFILE"))
      end

    %__MODULE__{code: code, source?: true, message: what <> " " <> hint}
  end

  @doc false
  def credentials_hint(profile) when profile in [nil, ""] do
    "Set AWS_PROFILE (with ~/.aws mounted), or AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and " <>
      "AWS_SESSION_TOKEN, for example with " <>
      "`eval \"$(aws configure export-credentials --profile <profile> --format env)\"`, then restart the viewer."
  end

  def credentials_hint(:container_full_uri) do
    "The host credential helper did not answer. Run `aws login --profile bundle-readonly` on the host."
  end

  def credentials_hint(profile) do
    "Run `aws sso login --profile #{profile}` on the host, then reload this page."
  end

  @doc "What to run when the source's own `?profile=` has no valid credentials."
  def profile_hint(profile) do
    "Run `aws login --profile #{profile}` (or `aws sso login --profile #{profile}`), then press Refresh."
  end

  def code(body) when is_binary(body), do: xml_value(body, "Code")
  def code(_), do: nil

  defp xml_value(body, tag) when is_binary(body) do
    case Regex.run(~r{<#{tag}>([^<]*)</#{tag}>}, body) do
      [_, v] -> v
      _ -> nil
    end
  end

  defp xml_value(_, _), do: nil
end

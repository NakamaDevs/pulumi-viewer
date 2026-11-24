defmodule PulumiViewer.CloudFormation.Error do
  @moduledoc "A CloudFormation read failed. The message is written for the person who runs the viewer."
  defexception [:message, :code]

  def from({:http_error, status, %{body: body}}), do: from_body(status, body)
  def from({:http_error, status, body}) when is_binary(body), do: from_body(status, body)
  def from(:no_credentials), do: credentials("AWS credentials are missing.")
  def from(:credential_helper), do: credentials("AWS credentials are missing.")
  def from(%__MODULE__{} = e), do: e
  def from(other), do: %__MODULE__{message: "CloudFormation read failed: #{inspect(other)}"}

  defp from_body(status, body) do
    code = xml_value(body, "Code")
    text = xml_value(body, "Message")

    case code do
      c when c in ["ExpiredToken", "ExpiredTokenException", "RequestExpired"] ->
        credentials("AWS credentials are expired.", c)

      c
      when c in [
             "InvalidClientTokenId",
             "UnrecognizedClientException",
             "SignatureDoesNotMatch",
             "MissingAuthenticationToken"
           ] ->
        credentials("AWS credentials are not valid.", c)

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

  defp credentials(what, code \\ nil) do
    hint =
      case PulumiViewer.CloudFormation.Client.credential_source() do
        :container_full_uri -> credentials_hint(:container_full_uri)
        _ -> credentials_hint(System.get_env("AWS_PROFILE"))
      end

    %__MODULE__{code: code, message: what <> " " <> hint}
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

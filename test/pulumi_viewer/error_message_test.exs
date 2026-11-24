defmodule PulumiViewer.ErrorMessageTest do
  use ExUnit.Case, async: false
  alias PulumiViewer.CloudFormation.Error

  test "any error term gives a readable message" do
    assert PulumiViewer.error_message(:not_found) == "Stack not found."
    assert PulumiViewer.error_message({:http_error, 403, %{body: "denied"}}) =~ "403"
    assert PulumiViewer.error_message(:enoent) =~ "enoent"
  end

  test "an ExAws crash with an AWS profile keeps the login hint" do
    saved = System.get_env("AWS_PROFILE")
    System.put_env("AWS_PROFILE", "bundle-readonly")

    on_exit(fn ->
      if saved, do: System.put_env("AWS_PROFILE", saved), else: System.delete_env("AWS_PROFILE")
    end)

    e = Error.from({:raised, "expected a map, got: nil"})
    assert e.source?
    assert e.message =~ "aws sso login --profile bundle-readonly"
    assert e.message =~ "expected a map, got: nil"
  end

  test "access denied on one stack is not a source-wide error" do
    body = "<Error><Code>AccessDenied</Code><Message>no</Message></Error>"
    refute Error.from({:http_error, 403, body}).source?
  end
end

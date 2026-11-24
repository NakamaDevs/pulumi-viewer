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

  test "a source profile gives the hint for that profile, not the global AWS_PROFILE" do
    saved = System.get_env("AWS_PROFILE")
    System.put_env("AWS_PROFILE", "global-profile")

    on_exit(fn ->
      if saved, do: System.put_env("AWS_PROFILE", saved), else: System.delete_env("AWS_PROFILE")
    end)

    hint =
      "Run `aws login --profile src-p` (or `aws sso login --profile src-p`), then press Refresh."

    expired = "<Error><Code>ExpiredToken</Code><Message>x</Message></Error>"
    invalid = "<Error><Code>InvalidClientTokenId</Code><Message>x</Message></Error>"

    for term <- [
          {:http_error, 403, expired},
          {:http_error, 403, %{body: invalid}},
          :no_credentials,
          {:raised, "expected a map, got: nil"}
        ] do
      e = Error.from(term, "src-p")
      assert e.source?, inspect(term)
      assert e.message =~ hint, inspect(term)
      refute e.message =~ "global-profile", inspect(term)
    end
  end

  test "a raise with a source profile keeps the hint even without a global profile" do
    saved = System.get_env("AWS_PROFILE")
    System.delete_env("AWS_PROFILE")
    on_exit(fn -> if saved, do: System.put_env("AWS_PROFILE", saved) end)

    e = Error.from({:raised, "boom"}, "src-p")
    assert e.source?
    assert e.message =~ "aws login --profile src-p"
  end

  test "access denied on one stack is not a source-wide error" do
    body = "<Error><Code>AccessDenied</Code><Message>no</Message></Error>"
    refute Error.from({:http_error, 403, body}).source?
  end
end

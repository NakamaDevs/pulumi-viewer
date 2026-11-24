defmodule PulumiViewer.SourcesTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.Sources

  test "parses ;-separated name=url entries" do
    assert [
             %{name: "pulumi", url: "file:///state/pulumi", kind: :pulumi},
             %{name: "cloudformation", url: "cloudformation://us-east-1", kind: :cloudformation}
           ] =
             Sources.parse(
               "pulumi=file:///state/pulumi;cloudformation=cloudformation://us-east-1"
             )
  end

  test "parses one entry per line, ignores blanks and spaces" do
    assert [%{name: "a", url: "s3://b/p"}, %{name: "c", url: "file://x"}] =
             Sources.parse("\n a = s3://b/p \n\nc=file://x\n")
  end

  test "an entry without a name, or a duplicate name, is an error" do
    assert_raise ArgumentError, ~r/name=url/, fn -> Sources.parse("file://x") end
    assert_raise ArgumentError, ~r/twice/, fn -> Sources.parse("a=file://x;a=file://y") end
  end

  test "an unknown scheme is an error" do
    assert_raise ArgumentError, ~r/ftp/, fn -> Sources.parse("a=ftp://x") end
  end

  test "PULUMI_BACKEND_URL alone is one source named default" do
    assert [%{name: "default", url: "file://x", kind: :pulumi}] = Sources.resolve(nil, "file://x")
    assert [%{name: "p"}] = Sources.resolve("p=file://y", "file://x")
  end
end

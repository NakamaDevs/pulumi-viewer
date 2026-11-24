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

  describe "comma lists and profiles (the PULUMI_BACKEND_URLS form)" do
    test "a comma starts a new entry; a comma inside a query value stays" do
      assert [
               %{name: "dev", url: "cloudformation://us-east-1?prefix=a,b&profile=p"},
               %{name: "local", url: "file://test/fixtures/state"}
             ] =
               PulumiViewer.Sources.parse(
                 "dev=cloudformation://us-east-1?prefix=a,b&profile=p, local=file://test/fixtures/state"
               )
    end

    test "each AWS source keeps its own profile and name" do
      assert {PulumiViewer.CloudFormation, %{profile: "bundle-dev", name: "dev"}} =
               PulumiViewer.Storage.for_source(%{
                 name: "dev",
                 url: "cloudformation://us-east-1?profile=bundle-dev"
               })

      assert {PulumiViewer.Storage.S3, %{bucket: "state", profile: "bundle-prod", name: "prod"}} =
               PulumiViewer.Storage.for_source(%{
                 name: "prod",
                 url: "s3://state?profile=bundle-prod"
               })
    end
  end
end

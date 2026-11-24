defmodule PulumiViewer.CloudFormation.TemplateTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.CloudFormation.Template

  @dir "test/fixtures/cloudformation"

  test "parses YAML short-form tags into long form" do
    {:ok, t} = Template.parse(File.read!("#{@dir}/template.yaml"))
    props = t["Resources"]["Policy"]["Properties"]
    assert props["Bucket"] == %{"Ref" => "Bucket"}
    assert t["Resources"]["Bucket"]["Properties"]["Ports"] == [80, 443]
    assert t["Outputs"]["Url"]["Value"] == %{"Fn::GetAtt" => ["Distribution", "DomainName"]}
  end

  test "extracts resource references from YAML: Ref, GetAtt, Sub and DependsOn" do
    {:ok, t} = Template.parse(File.read!("#{@dir}/template.yaml"))
    deps = Template.dependencies(t)
    assert deps["Bucket"] == []
    assert deps["Policy"] == ["Bucket"]
    assert deps["Distribution"] == ["Bucket", "Policy"]
  end

  test "extracts references from JSON and ignores pseudo parameters" do
    {:ok, t} = Template.parse(File.read!("#{@dir}/template.json"))
    assert Template.dependencies(t) == %{"Fn" => ["Role"], "Role" => []}
  end

  test "rejects a broken template" do
    assert {:error, _} = Template.parse("Resources: [unclosed")
  end
end

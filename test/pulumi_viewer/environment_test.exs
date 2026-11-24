defmodule PulumiViewer.EnvironmentTest do
  use ExUnit.Case, async: true
  alias PulumiViewer.Environment

  describe "Pulumi stacks" do
    test "the stack name is the environment" do
      assert Environment.of(:pulumi, "dev") == {:env, "dev"}
      assert Environment.of(:pulumi, "prod") == {:env, "prod"}
      assert Environment.of(:pulumi, "staging") == {:env, "staging"}
    end

    test "shared, ci and other names are account-wide" do
      assert Environment.of(:pulumi, "shared") == {:account, "shared"}
      assert Environment.of(:pulumi, "ci") == {:account, "ci"}
      assert Environment.of(:pulumi, "sandbox") == {:account, "sandbox"}
    end

    test "<project>-<env> and <env>-<anything>" do
      assert Environment.of(:pulumi, "web-prod") == {:env, "prod"}
      assert Environment.of(:pulumi, "dev-hector") == {:env, "dev"}
    end
  end

  describe "CloudFormation stacks" do
    test "the first environment token of the name" do
      assert Environment.of(:cloudformation, "quickbuy-prod-site") == {:env, "prod"}
      assert Environment.of(:cloudformation, "prod-alerts") == {:env, "prod"}
      assert Environment.of(:cloudformation, "wayfair-lake-dev-access") == {:env, "dev"}
      assert Environment.of(:cloudformation, "wayfair-lake-dev") == {:env, "dev"}
      assert Environment.of(:cloudformation, "wayfair-prod") == {:env, "prod"}
    end

    test "shared, ci or no token is account-wide" do
      assert Environment.of(:cloudformation, "ci-runners") == {:account, "ci"}
      assert Environment.of(:cloudformation, "shared-dns") == {:account, "shared"}
      assert Environment.of(:cloudformation, "github-oidc") == {:account, "shared"}
      assert Environment.of(:cloudformation, "devtools") == {:account, "shared"}
    end
  end

  test "group order: environments first, then account-wide" do
    groups = [
      {:account, "ci"},
      {:env, "prod"},
      {:account, "shared"},
      {:env, "dev"},
      {:env, "staging"}
    ]

    assert Enum.sort_by(groups, &Environment.sort_key/1) ==
             [
               {:env, "dev"},
               {:env, "staging"},
               {:env, "prod"},
               {:account, "ci"},
               {:account, "shared"}
             ]
  end
end

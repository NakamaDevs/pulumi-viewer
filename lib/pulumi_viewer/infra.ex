defmodule PulumiViewer.Infra do
  @moduledoc "Ash domain over Pulumi state. Read-only."
  use Ash.Domain, otp_app: :pulumi_viewer

  resources do
    resource PulumiViewer.Infra.Stack do
      define :list_stacks, action: :read, args: [{:optional, :source}]
    end

    resource PulumiViewer.Infra.Resource do
      define :list_resources, action: :for_stack, args: [:project, :stack, {:optional, :source}]
    end

    resource PulumiViewer.Infra.Update do
      define :list_updates, action: :for_stack, args: [:project, :stack, {:optional, :source}]
    end
  end
end

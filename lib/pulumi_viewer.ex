defmodule PulumiViewer do
  @moduledoc "Read-only viewer for Pulumi DIY backends (S3 or local files, also on an AWS emulator)."

  @doc "Backend URL plus the S3 endpoint when one is set, for the header."
  def backend_label do
    url = Application.get_env(:pulumi_viewer, :backend_url, "")

    case System.get_env("AWS_ENDPOINT_URL_S3") || System.get_env("AWS_ENDPOINT_URL") do
      nil -> url
      ep -> "#{url} @ #{ep}"
    end
  end
end

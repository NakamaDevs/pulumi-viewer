defmodule PulumiViewer do
  @moduledoc "Read-only viewer for Pulumi DIY backends (S3 or local files, also on an AWS emulator)."

  @doc "A short message for an error, without the Ash wrapper and stack trace of a source error."
  def error_message(%PulumiViewer.CloudFormation.Error{message: m}), do: m

  def error_message(e) do
    case find_source_error(e) do
      nil -> Exception.message(e)
      inner -> inner.message
    end
  end

  defp find_source_error(%PulumiViewer.CloudFormation.Error{} = e), do: e

  defp find_source_error(%{errors: errors}) when is_list(errors),
    do: Enum.find_value(errors, &find_source_error/1)

  defp find_source_error(%{error: inner}), do: find_source_error(inner)

  # Ash keeps an unknown error as its formatted text
  defp find_source_error("** (PulumiViewer.CloudFormation.Error) " <> msg),
    do: %PulumiViewer.CloudFormation.Error{message: msg}

  defp find_source_error(_), do: nil

  @doc "Backend URL plus the S3 endpoint when one is set, for the header."
  def backend_label do
    url = Application.get_env(:pulumi_viewer, :backend_url, "")

    case System.get_env("AWS_ENDPOINT_URL_S3") || System.get_env("AWS_ENDPOINT_URL") do
      nil -> url
      ep -> "#{url} @ #{ep}"
    end
  end
end

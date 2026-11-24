defmodule PulumiViewer.RuntimeConfigTest do
  # Changes process environment variables, so it does not run async.
  use ExUnit.Case, async: false

  @vars ~w(PULUMI_VIEWER_SOURCES PULUMI_BACKEND_URLS)

  setup do
    saved = Map.new(@vars, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(saved, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)
    end)
  end

  defp sources,
    do: Config.Reader.read!("config/runtime.exs", env: :test)[:pulumi_viewer][:sources]

  test "an empty PULUMI_VIEWER_SOURCES counts as unset, so PULUMI_BACKEND_URLS is used" do
    System.put_env("PULUMI_VIEWER_SOURCES", "")
    System.put_env("PULUMI_BACKEND_URLS", "a=file://x")
    assert sources() == "a=file://x"
  end

  test "PULUMI_VIEWER_SOURCES wins when it is set" do
    System.put_env("PULUMI_VIEWER_SOURCES", "b=file://y")
    System.put_env("PULUMI_BACKEND_URLS", "a=file://x")
    assert sources() == "b=file://y"
  end
end

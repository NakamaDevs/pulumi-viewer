defmodule PulumiViewerWeb.PageController do
  use PulumiViewerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

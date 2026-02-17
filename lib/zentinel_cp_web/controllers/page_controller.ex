defmodule ZentinelCpWeb.PageController do
  use ZentinelCpWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/projects")
  end
end

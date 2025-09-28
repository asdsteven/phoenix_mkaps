defmodule MkapsWeb.ExperimentLive do
  use MkapsWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <canvas class="w-[1280px] h-[720px] touch-none select-none" phx-hook="Experiment" id="canvas" width="3840" height="2160"></canvas>
    """
  end
end

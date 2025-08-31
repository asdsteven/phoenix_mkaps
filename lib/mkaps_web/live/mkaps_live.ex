defmodule MkapsWeb.MkapsLive do
  use MkapsWeb, :live_view

  def mount(_params, _session, socket) do
    slides = [
      "開學了，馬鳴加收到五個新書包。",
      "五個書包五種顏色，馬鳴加都喜歡。",
      "媽媽說：「先用一個，壞了再換一個吧。」"
    ]
    {:ok,
     assign(socket,
       slides: slides,
       slide_index: 0,
       positions: %{}
     )}
  end

  def handle_event("update_position", %{"x" => x, "y" => y}, socket) do
    idx = socket.assigns.slide_index
    new_positions = Map.put(socket.assigns.positions, idx, %{x: x, y: y})
    {:noreply, assign(socket, positions: new_positions)}
  end

  def handle_event("prev", _params, socket) do
    {:noreply, update(socket, :slide_index, &max(&1 - 1, 0))}
  end

  def handle_event("next", _params, socket) do
    {:noreply, update(socket, :slide_index, &min(&1 + 1, length(socket.assigns.slides) - 1))}
  end
end

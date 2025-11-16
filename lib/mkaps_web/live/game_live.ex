defmodule MkapsWeb.GameLive do
  use MkapsWeb, :live_view
  import Ecto.Query, only: [order_by: 2, preload: 2, where: 3, first: 2]
  alias Mkaps.Game
  alias Mkaps.Pad
  alias Mkaps.Repo

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_info(%{"pad" => pad}, socket) do
    {:noreply,
     socket
     |> update(:game, &update_game_pad(&1, pad))
     |> push_event("draw", %{id: pad.id, strokes: pad.strokes})}
  end

  def handle_info(%{"question" => question}, socket) do
    {:noreply,
     socket
     |> assign(question: question)}
  end

  def handle_params(_params, _uri, socket)
      when socket.assigns.live_action == :index do
    {:noreply,
     socket
     |> assign(games: Game |> order_by([desc: :position]) |> Repo.all)
     |> assign(game_changes: %{})}
  end

  def handle_params(%{"game_id" => game_id}, _uri, socket)
      when socket.assigns.live_action == :show do
    Phoenix.PubSub.subscribe(Mkaps.PubSub, "game-pad:#{game_id}")
    {:noreply,
     socket
     |> assign(game: Game |> preload(:pads) |> Repo.get!(String.to_integer(game_id)))}
  end

  def handle_params(%{"game_id" => game_id}, _uri, socket)
      when socket.assigns.live_action == :edit do
    {:noreply,
     socket
     |> assign(game: Game |> preload(:pads) |> Repo.get!(String.to_integer(game_id)))
     |> assign(game_changes: %{})}
  end

  def handle_params(%{"game_id" => game_id}, _uri, socket)
      when socket.assigns.live_action == :index_pads do
    {:noreply,
     socket
     |> assign(game: Game |> preload(:pads) |> Repo.get!(String.to_integer(game_id)))}
  end

  def handle_params(%{"game_id" => game_id, "pad_id" => pad_id}, _uri, socket)
      when socket.assigns.live_action == :show_pad do
    Phoenix.PubSub.subscribe(Mkaps.PubSub, "game-question:#{game_id}")
    game = Game |> preload(:pads) |> Repo.get!(String.to_integer(game_id))
    {:noreply,
     socket
     |> assign(game: game)
     |> assign(pad: Pad |> Repo.get!(String.to_integer(pad_id)))
     |> assign(question: Map.get(game.data, "question"))}
  end

  def render(assigns) do
    case assigns.live_action do
      :index -> index(assigns)
      :show -> show_game(assigns)
      :edit -> edit(assigns)
      :index_pads -> index_pads(assigns)
      :show_pad -> show_pad(assigns)
    end
  end

  attr :form, :any, required: true
  attr :change_key, :string, required: true
  attr :updated_at, :any, required: true
  defp index_game(assigns) do
    ~H"""
    <.form for={@form} phx-submit="submit-game" phx-change="change-game" class="m-2 flex items-center gap-x-1">
      <input :if={@form[:id].value} type="hidden" name={@form[:id].name} value={@form[:id].value} />
      <input type="hidden" name="change_key" value={@change_key} />
      <input type="hidden" name={@form[:position].name} value={@form[:position].value} />
      <span :if={@form[:id].value} class="text-info-content">{@form[:position].value}</span>
      <div class="join">
        <input class={["join-item input", Map.has_key?(@form.source.changes, :name) && "input-primary"]}
          type="text" placeholder="Game name" name={@form[:name].name} value={@form[:name].value} />
        <button class="join-item btn btn-primary" type="submit" disabled={@form.source.changes == %{}}>
          {if @form[:id].value, do: "Save", else: "Create"}
        </button>
      </div>
      <button disabled={@form.source.changes != %{}}
        :if={@form[:id].value} type="button" class="btn btn-error" type="error" phx-click="delete-game" phx-value-game={@form[:id].value}>Delete</button>
      <div :if={@form[:id].value} class="join">
        <button type="button" class="join-item btn btn-secondary" phx-click="move-game" phx-value-game={@form[:id].value}>Move Up</button>
        <.link class="join-item btn btn-secondary" patch={~p"/games/#{@form[:id].value}/edit"}>Edit</.link>
        <.link class="join-item btn btn-accent" patch={~p"/games/#{@form[:id].value}"}>Play</.link>
      </div>
      <div :if={@updated_at} class="inline-block text-xs text-center">
        {@updated_at |> DateTime.add(8 * 3600, :second) |> Calendar.strftime("%Y-%m-%d")}<br>
        {@updated_at |> DateTime.add(8 * 3600, :second) |> Calendar.strftime("%H:%M:%S")}
      </div>
    </.form>
    """
  end

  attr :games, :list, required: true
  defp index(assigns) do
    ~H"""
    <div id="idle-check" phx-hook="IdleDisconnect"></div>
    <div class="breadcrumbs">
      <ul>
        <li><.link patch={~p"/lessons"}>Lessons</.link></li>
        <li>Games</li>
      </ul>
    </div>
    <%= if length(@games) == 0 do %>
    <.index_game change_key="first" updated_at={nil}
      form={to_form(Game.changeset(%Game{position: 1}, Map.get(@game_changes, "first", %{})))} />
    <% end %>
    <%= for game <- @games do %>
    <.index_game :if={game.id == Enum.at(@games, 0).id} change_key={"after-#{game.id}"} updated_at={nil}
      form={to_form(Game.changeset(%Game{position: game.position+1}, Map.get(@game_changes, "after-#{game.id}", %{})))} />
    <.index_game change_key={"#{game.id}"} updated_at={game.updated_at}
      form={to_form(Game.changeset(game, Map.get(@game_changes, "#{game.id}", %{})))} />
    <% end %>
    """
  end

  attr :game, Game, required: true
  defp show_game(assigns) do
    ~H"""
    <div class="flex" :for={row <- String.split(@game.layout, "\n", trim: true)}>
      <div class={["w-1/6 border-1", name == "沒有人" && "bg-gray-500"]} :for={name <- String.split(row, " ", trim: true)}>
        <canvas width="2000" height="1600" class="w-full" :if={name != "沒有人"}
          phx-hook="SmallPad" id={"pad-#{Enum.find(@game.pads, fn pad -> pad.name == name end).id}"}
          data-id={Enum.find(@game.pads, fn pad -> pad.name == name end).id}></canvas>
      </div>
    </div>
    <div>
      <button class="btn btn-outline" :for={q <- Map.get(@game.data, "questions")} phx-click="set-question" phx-value-question={q}>{q}</button>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :change_key, :string, required: true
  def edit_game(assigns) do
    ~H"""
    <.form for={@form} phx-submit="submit-game" phx-change="change-game" class="m-2 flex">
      <input type="hidden" name="change_key" value={@change_key} />
      <input type="hidden" name={@form[:id].name} value={@form[:id].value} />
      <input type="hidden" name={@form[:position].name} value={@form[:position].value} />
      <span :if={@form[:id].value}>{@form[:position].value}</span>
      <textarea class={["textarea", Map.has_key?(@form.source.changes, :layout) && "textarea-primary",
        !@form[:id].value && @form.source.changes == %{} && "h-fit min-h-fit"]}
        rows={!@form[:id].value && !Enum.any?([:layout, :data], &(Map.has_key?(@form.source.changes, &1))) && 1}
        name={@form[:layout].name} placeholder="Layout">{@form[:layout].value}</textarea>
      <textarea class={["textarea", Map.has_key?(@form.source.changes, :data) && "textarea-primary",
        !@form[:id].value && @form.source.changes == %{} && "h-fit min-h-fit"]}
        rows={!@form[:id].value && !Enum.any?([:layout, :data], &(Map.has_key?(@form.source.changes, &1))) && 1}
        name={@form[:data].name} placeholder="Data">{@form[:data].value && Jason.encode!(@form[:data].value)}</textarea>
      <button class="btn btn-primary" type="submit" disabled={@form.source.changes == %{}}>Save</button>
    </.form>
    """
  end

  attr :game, Game, required: true
  defp edit(assigns) do
    ~H"""
    <div id="idle-check" phx-hook="IdleDisconnect"></div>
    <div class="breadcrumbs">
      <ul>
        <li><.link patch={~p"/lessons"}>Lessons</.link></li>
        <li><.link patch={~p"/games"}>Games</.link></li>
        <li>Edit game</li>
      </ul>
    </div>
    <.edit_game form={to_form(Game.changeset(@game, Map.get(@game_changes, "#{@game.id}", %{})))}
      change_key={@game.id} />
    """
  end

  attr :game, Game, required: true
  defp index_pads(assigns) do
    ~H"""
    <div class="flex" :for={row <- String.split(@game.layout, "\n", trim: true)}>
      <div class="basis-1/5 text-center py-5" :for={name <- String.split(row, " ", trim: true)}>
        <.link patch={~p"/games/#{@game.id}/pads/#{Enum.find(@game.pads, fn pad -> pad.name == name end).id}"} class={["btn btn-primary btn-xl kai", name == "沒有人" && "invisible"]}>{name}</.link>
      </div>
    </div>
    """
  end

  attr :game, Game, required: true
  attr :pad, Pad, required: true
  attr :question, :string, required: true
  defp show_pad(assigns) do
    ~H"""
    <div class="relative w-[1000px] h-[800px] m-auto">
      <div :if={@question && String.length(@question) == 1} class="absolute left-0 top-0 right-0 text-[700px] leading-none text-center text-gray-400 kai">{@question}</div>
      <div :if={@question && String.length(@question) == 2} class="absolute left-0 top-0 right-0 text-[400px] leading-none text-center text-gray-400 kai">{@question}</div>
      <canvas width="2000" height="1600" class="absolute w-[1000px] border-1 touch-none" phx-hook="Pad" id="pad"></canvas>
      <span class="absolute bg-white text-5xl -translate-x-1/2 text-black left-1/2 top-1 kai p-1">{@pad.name}</span>
      <button class="absolute btn btn-error btn-xl left-1 top-1 kai" phx-click="clear">清除</button>
      <button class="absolute btn btn-success btn-xl right-1 top-1 kai" phx-click="request_submit">提交</button>
    </div>
    """
  end

  def handle_event("change-game", %{"change_key" => change_key, "game" => params}, socket) do
    {:noreply,
     socket
     |> update(:game_changes, &Map.put(&1, change_key, params |> decode_data))}
  end

  def handle_event("submit-game", %{"change_key" => change_key, "game" => %{"id" => _} = params}, socket) do
    id = String.to_integer(params["id"])
    game = Game |> Repo.get!(id) |> Game.changeset(params |> decode_data) |> Repo.update!
    Enum.each(String.split(game.layout, [" ", "\n"], trim: true), fn name ->
      Pad.changeset(%Pad{game_id: id, name: name}, %{}) |> Repo.insert
    end)
    {:noreply,
     socket
     |> assign(games: Game |> order_by([desc: :position]) |> Repo.all)
     |> assign(game: game)
     |> update(:game_changes, &Map.delete(&1, change_key))}
  end

  def handle_event("submit-game", %{"change_key" => change_key, "game" => params}, socket) do
    {:ok, _} = Repo.transact(fn ->
      Game |> where([l], l.position >= ^params["position"]) |> Repo.update_all(inc: [position: 1])
      %Game{} |> Game.changeset(params |> decode_data) |> Repo.insert
    end)
    {:noreply,
     socket
     |> assign(games: Game |> order_by([desc: :position]) |> Repo.all)
     |> update(:game_changes, &Map.delete(&1, change_key))}
  end

  def handle_event("move-game", %{"game" => game_id}, socket) do
    {:ok, _} = Repo.transact(fn ->
      game = Game |> Repo.get!(String.to_integer(game_id))
      game_prev = Game |> where([l], l.position > ^game.position) |> first(:position) |> Repo.one!
      game |> Game.changeset(%{position: game_prev.position}) |> Repo.update!
      game_prev |> Game.changeset(%{position: game.position}) |> Repo.update
    end)
    {:noreply,
     socket
     |> assign(games: Game |> order_by([desc: :position]) |> Repo.all)}
  end

  def handle_event("delete-game", %{"game" => game_id}, socket) do
    {:ok, _} = Repo.transact(fn ->
      game = Game |> Repo.get!(String.to_integer(game_id))
      Game |> where([l], l.position > ^game.position) |> Repo.update_all(inc: [position: -1])
      game |> Repo.delete
    end)
    {:noreply,
     socket
     |> assign(games: Game |> order_by([desc: :position]) |> Repo.all)}
  end

  def handle_event("set-question", %{"question" => question}, socket) do
    game = socket.assigns.game
    new_game = game |> Game.changeset(%{data: Map.put(game.data, "question", question)}) |> Repo.update!
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "game-question:#{game.id}", %{"question" => question})
    {:noreply,
     socket
     |> assign(game: new_game)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, push_event(socket, "clear", %{})}
  end

  def handle_event("request_submit", _params, socket) do
    {:noreply, push_event(socket, "request_submit", %{})}
  end

  def handle_event("submit", strokes, socket) do
    pad = Pad |> Repo.get!(socket.assigns.pad.id) |> Pad.changeset(%{strokes: %{list: strokes}}) |> Repo.update!
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "game-pad:#{pad.game_id}", %{"pad" => pad})
    {:noreply, socket}
  end

  def handle_event("init", _params, socket) do
    pad = Pad |> Repo.get!(socket.assigns.pad.id)
    {:noreply, push_event(socket, "init", pad.strokes || %{"list" => []})}
  end

  def handle_event("smallpad-init", %{"id" => pad_id}, socket) do
    id = String.to_integer(pad_id)
    pad = Pad |> Repo.get!(id)
    {:noreply, push_event(socket, "draw", %{"id" => pad_id, "strokes" => pad.strokes || %{"list" => []}})}
  end

  defp decode_data(params) do
    case Map.get(params, "data", "") do
      "" -> Map.put(params, "data", nil)
      "{}" -> Map.put(params, "data", nil)
      data ->
        case Jason.decode(data) do
          {:ok, decode} -> %{params | "data" => decode}
          {:error, _} -> Map.delete(params, "data")
        end
    end
  end

  defp update_game_pad(game, pad) do
    pads = Enum.map(game.pads, fn s -> if s.id == pad.id, do: pad, else: s end)
    %{game | pads: pads}
  end
end

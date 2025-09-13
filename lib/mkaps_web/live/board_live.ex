defmodule MkapsWeb.BoardLive do
  use MkapsWeb, :live_view
  import Ecto.Query, only: [order_by: 2, preload: 2, where: 2, where: 3, last: 2, first: 2]
  alias Mkaps.Lesson
  alias Mkaps.Slide
  alias Mkaps.Repo

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(highlights: MapSet.new())
     |> assign(image_frames: %{})
     |> assign(toggle_scroll: false, toggle_sentences: false, toggle_images: false)
     |> assign(transforms_state: :pending)
     |> assign(toggle_pan: true, toggle_zoom: false, toggle_rotate: false)
     |> assign(lesson: nil)
     |> allow_upload(:image,
                     accept: :any,
                     max_file_size: 1_000_000_000,
                     progress: fn :image, entry, socket -> {:noreply, assign(socket, progress: entry.progress)} end)}
  end

  def handle_params(_params, _uri, socket)
      when socket.assigns.live_action == :index do
    {:noreply,
     socket
     |> assign(lessons: Lesson |> order_by([desc: :position]) |> Repo.all)
     |> assign(lesson_changes: %{})}
  end

  def handle_params(%{"lesson_id" => lesson_id}, _uri, socket)
      when socket.assigns.live_action == :edit do
    {:noreply,
     socket
     |> assign(lesson: Lesson |> preload(:slides) |> Repo.get!(String.to_integer(lesson_id)))
     |> assign(slide_changes: %{})
     |> assign(progress: 0, uploaded_images: get_uploaded_images())}
  end

  def handle_params(%{"lesson_id" => lesson_id, "slide_position" => slide_position}, _uri, socket)
      when socket.assigns.live_action == :show do
    id = String.to_integer(lesson_id)
    position = String.to_integer(slide_position)
    lesson =
      case socket.assigns.lesson do
        %Lesson{id: ^id} = lesson -> lesson
        _ -> Lesson |> preload(:slides) |> Repo.get!(id)
      end
    slide = Enum.find(lesson.slides, &(&1.position == position))
    {:noreply,
     socket
     |> assign(lesson: lesson)
     |> assign(slide: slide)
     |> assign(slide_position: position)
     |> assign(auto_transforms: slide && auto_transform(slide))
     |> assign(transforms_state: :pending)
     |> assign(focus_id: nil)}
  end

  def render(assigns) do
    case assigns.live_action do
      :index -> index(assigns)
      :edit -> edit(assigns)
      :show -> show_slide(assigns)
    end
  end

  attr :form, :any, required: true
  defp index_lesson(assigns) do
    ~H"""
    <.form for={@form} phx-submit="submit-lesson" phx-change="change-lesson" class="m-2">
      <span :if={@form[:position].value}>{@form[:position].value}</span>
      <input :if={@form[:id].value} type="hidden" name={@form[:id].name} value={@form[:id].value} />
      <div class="join">
        <input class={["join-item input", Map.has_key?(@form.source.changes, :name) && "input-primary"]}
          type="text" placeholder="Lesson name" name={@form[:name].name} value={@form[:name].value} />
        <button class="join-item btn btn-primary" type="submit" disabled={@form.source.changes == %{}}>Submit</button>
      </div>
      <div :if={@form[:id].value} class="join">
        <button type="button" class="join-item btn btn-secondary" phx-click="move-lesson" phx-value-lesson={@form[:id].value}>Move Up</button>
        <.link class="join-item btn btn-secondary" patch={~p"/lessons/#{@form[:id].value}/edit"}>Edit</.link>
        <.link class="join-item btn btn-accent" patch={~p"/lessons/#{@form[:id].value}/slides/1"}>Play</.link>
      </div>
    </.form>
    """
  end

  attr :lessons, :list, required: true
  attr :lesson_changes, :map, required: true
  defp index(assigns) do
    ~H"""
    <div class="breadcrumbs">
      <ul>
        <li>Lessons</li>
      </ul>
    </div>
    <.index_lesson form={to_form(Lesson.changeset(%Lesson{}, Map.get(@lesson_changes, -1, %{})))} />
    <.index_lesson :for={lesson <- @lessons} form={to_form(Lesson.changeset(lesson, Map.get(@lesson_changes, lesson.id, %{})))} />
    """
  end

  attr :form, :any, required: true
  defp edit_slide(assigns) do
    ~H"""
    <.form for={@form} phx-submit="submit-slide" phx-change="change-slide" class="m-2 flex">
      <span :if={@form[:position].value}>{@form[:position].value}</span>
      <input type="hidden" name={@form[:lesson_id].name} value={@form[:lesson_id].value} />
      <input :if={@form[:id].value} type="hidden" name={@form[:id].name} value={@form[:id].value} />
      <textarea class={["textarea", Map.has_key?(@form.source.changes, :sentences) && "textarea-primary"]}
        name={@form[:sentences].name} placeholder="Sentences">{@form[:sentences].value}</textarea>
      <textarea class={["textarea", Map.has_key?(@form.source.changes, :images) && "textarea-primary"]}
        name={@form[:images].name} placeholder="Images">{@form[:images].value}</textarea>
      <button class="btn btn-primary" type="submit" disabled={@form.source.changes == %{}}>Submit</button>
      <div :if={@form[:id].value} class="join">
        <button class="join-item btn btn-secondary" type="button" phx-click="move-slide" phx-value-slide={@form[:id].value}>Move</button>
        <.link class="join-item btn btn-accent" patch={~p"/lessons/#{@form[:lesson_id].value}/slides/#{@form[:position].value}"}>Play</.link>
      </div>
      <div :if={@form[:images].value}>
        <img class="h-24 w-auto inline m-1"
          :for={image <- String.split(@form[:images].value, "\n")}
          src={Enum.at(String.split(image, " "), 0)} />
      </div>
      <textarea class={["textarea", Map.has_key?(@form.source.changes, :transforms) && "textarea-primary"]}
        name={@form[:transforms].name} placeholder="Transforms">{Jason.encode!(@form[:transforms].value)}</textarea>
    </.form>
    """
  end

  attr :lesson, Lesson, required: true
  attr :slide_changes, :map, required: true
  attr :progress, :integer, required: true
  attr :uploaded_images, :list, required: true
  defp edit(assigns) do
    ~H"""
    <div class="breadcrumbs">
      <ul>
        <li><.link patch={~p"/lessons"}>Lessons</.link></li>
        <li>Edit lesson</li>
      </ul>
    </div>
    <.edit_slide :for={slide <- @lesson.slides} form={to_form(Slide.changeset(slide, Map.get(@slide_changes, slide.id, %{})))} />
    <.edit_slide form={to_form(Slide.changeset(%Slide{lesson_id: @lesson.id}, Map.get(@slide_changes, -1, %{})))} />
    <form phx-submit="submit-image" phx-change="change-image" class="m-2">
      <.live_file_input upload={@uploads.image} class="file-input file-input-primary" />
      <button type="submit">Upload</button>
      <div>{@progress}</div>
    </form>
    <div>Click one of them to copy image link</div>
    <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
      <div class="flex flex-col items-center space-y-2"
        :for={image <- @uploaded_images}
        phx-hook="CopyOnClick" id={"image-#{image}"} data-copy-text={"/uploads/#{image}"}>
        <span>{image}</span>
        <img src={"/uploads/#{image}"} class="w-full max-w-xs max-h-64 object-contain" />
      </div>
    </div>
    """
  end

  attr :sentences, :string, required: true
  attr :transforms, :map, required: true
  attr :auto_transforms, :map, required: true
  attr :slide_id, :integer, required: true
  attr :highlights, :map, required: true
  defp show_sentences(assigns) do
    ~H"""
    <span class={["absolute w-max max-w-[1200px] px-[0.4em] py-[0.1em]",
      "rounded-lg bg-stone-100 shadow-sm/100 text-black leading-[1.1] kai",
      "cursor-grab mkaps-touch-drag mkaps-sentence"]}
      :for={{sentence, i} <- Enum.with_index(String.split(@sentences, "\n"))}
      phx-hook="Touchable" id={"sentence-#{i}"}
      style={get_sentence_style(@transforms, @auto_transforms, "sentence-#{i}")}>
      <span :for={{{grapheme, deco}, j} <- Enum.with_index(graphemes(sentence))}
        phx-hook="Touchable" id={"#{@slide_id}-#{i}-#{j}"}
        class={["inline-block mkaps-touch-tap mkaps-grapheme",
          "#{@slide_id}-#{i}-#{j}" in @highlights && "text-violet-900 bg-violet-200",
          "#{@slide_id}-#{i}-#{j-1}" not in @highlights && "rounded-l-md",
          "#{@slide_id}-#{i}-#{j+1}" not in @highlights && "rounded-r-md",
          deco == "underline" && "underline underline-offset-[0.15em]"]}>
        {if grapheme == " ", do: "&nbsp;", else: grapheme}
      </span>
    </span>
    """
  end

  attr :images, :string, required: true
  attr :transforms, :map, required: true
  attr :auto_transforms, :map, required: true
  attr :slide_id, :integer, required: true
  attr :image_frames, :map, required: true
  defp show_images(assigns) do
    ~H"""
    <img class="absolute h-auto shadow-sm/100 rounded-lg cursor-grab mkaps-touch-drag mkaps-touch-tap mkaps-image"
      draggable="false"
      :for={{image, i} <- Enum.with_index(String.split(@images, "\n"))}
      src={Enum.at(String.split(image, " "), Map.get(@image_frames, "#{@slide_id}-#{i}", 0))}
      phx-hook="Touchable" id={"image-#{i}"}
      style={get_image_style(@transforms, @auto_transforms, "image-#{i}")} />
    """
  end

  attr :hue, :integer, required: true
  defp show_avatars_ui(assigns) do
    ~H"""
    <div class="join">
      <button class="join-item btn btn-sm kai btn-outline"
        phx-click="badge" phx-value-badge="👍">👍</button>
      <button class="join-item btn btn-sm kai btn-outline"
        phx-click="badge" phx-value-badge="⭐">⭐</button>
      <button class="join-item btn btn-sm kai btn-outline"
        phx-click="badge" phx-value-badge="❤️">❤️</button>
      <button class="join-item btn btn-sm kai btn-outline"
        phx-click="delete-badge">X</button>
    </div>
    <div class="join">
      <button class="join-item btn btn-sm kai btn-outline" phx-click="hue-left">&lt;</button>
      <button class="join-item btn btn-sm btn-outline" disabled>{@hue}</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="hue-right">&gt;</button>
    </div>
    """
  end

  attr :toggle_scroll, :boolean, required: true
  attr :toggle_sentences, :boolean, required: true
  attr :toggle_images, :boolean, required: true
  defp show_toggle_background_gestures(assigns) do
    ~H"""
    <div class="join tooltip tooltip-right" data-tip="輕觸背景滾動，或操控所有字/圖">
      <button class={"join-item btn btn-sm kai #{if @toggle_scroll, do: "btn-primary", else: "btn-outline"}"}
        phx-click="toggle-scroll">滾</button>
      <button class={"join-item btn btn-sm kai #{if @toggle_sentences, do: "btn-primary", else: "btn-outline"}"}
        phx-click="toggle-sentences">字</button>
      <button class={"join-item btn btn-sm kai #{if @toggle_images, do: "btn-primary", else: "btn-outline"}"}
        phx-click="toggle-images">圖</button>
    </div>
    """
  end

  attr :transforms_state, :atom, required: true
  attr :transforms, :map, required: true
  defp show_save_transforms(assigns) do
    ~H"""
    <div class="join tooltip tooltip-right" data-tip="存取物件位置表">
      <%= if @transforms_state == :pending do %>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="save-transforms">存</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="apply-transforms">用</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="clear-transforms" disabled={not Map.has_key?(@transforms, "")}>清</button>
      <% end %>
      <%= if @transforms_state == :save do %>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="cancel-transforms">取消</button>
      <button class={"join-item btn btn-sm kai #{if Map.has_key?(@transforms, "1"), do: "btn-primary", else: "btn-outline"}"}
        phx-click="save-transforms" phx-value-slot="1">存入位置表一</button>
      <button class={"join-item btn btn-sm kai #{if Map.has_key?(@transforms, "2"), do: "btn-primary", else: "btn-outline"}"}
        phx-click="save-transforms" phx-value-slot="2">存入位置表二</button>
      <% end %>
      <%= if @transforms_state == :apply do %>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="cancel-transforms">取消</button>
      <button class="join-item btn btn-sm kai btn-outline"
        phx-click="apply-transforms" phx-value-slot="1" disabled={not Map.has_key?(@transforms, "1")}>應用位置表一</button>
      <button class="join-item btn btn-sm kai btn-outline"
        phx-click="apply-transforms" phx-value-slot="2" disabled={not Map.has_key?(@transforms, "2")}>應用位置表二</button>
      <% end %>
    </div>
    """
  end

  attr :toggle_pan, :boolean, required: true
  attr :toggle_zoom, :boolean, required: true
  attr :toggle_rotate, :boolean, required: true
  defp show_toggle_gestures(assigns) do
    ~H"""
    <div class="join tooltip tooltip-right" data-tip="啟用輕觸動作移動、縮放、旋轉">
      <button class={"join-item btn btn-sm kai #{if @toggle_pan, do: "btn-primary", else: "btn-outline"}"}
        phx-click="toggle-pan">移</button>
      <button class={"join-item btn btn-sm kai #{if @toggle_zoom, do: "btn-primary", else: "btn-outline"}"}
        phx-click="toggle-zoom">放</button>
      <button class={"join-item btn btn-sm kai #{if @toggle_rotate, do: "btn-primary", else: "btn-outline"}"}
        phx-click="toggle-rotate">旋</button>
    </div>
    """
  end

  attr :highlights, :map, required: true
  attr :image_frames, :map, required: true
  attr :toggle_scroll, :boolean, required: true
  attr :toggle_sentences, :boolean, required: true
  attr :toggle_images, :boolean, required: true
  attr :transforms_state, :atom, required: true
  attr :toggle_pan, :boolean, required: true
  attr :toggle_zoom, :boolean, required: true
  attr :toggle_rotate, :boolean, required: true
  attr :lesson, Lesson, required: true
  attr :slide, Slide, required: true
  attr :slide_position, :integer, required: true
  attr :auto_transforms, :map, required: true
  attr :focus_id, :string, required: true
  defp show_slide(assigns) do
    ~H"""
    <div class={["w-[1280px] h-[720px] bg-[url(/images/background1.jpg)] bg-cover bg-center relative overflow-hidden select-none",
      (@toggle_sentences || @toggle_images) && "cursor-grab"]}
      phx-hook="Touchable" id="background"
      data-toggle-scroll={@toggle_scroll} data-toggle-sentences={@toggle_sentences} data-toggle-images={@toggle_images}
      data-toggle-pan={@toggle_pan} data-toggle-zoom={@toggle_zoom} data-toggle-rotate={@toggle_rotate}>
      <div class="absolute inset-0 bg-zinc-800/90"></div>
      <.show_sentences :if={@slide && @slide.sentences} sentences={@slide.sentences}
        transforms={Map.get(@slide.transforms || %{}, "", %{})} auto_transforms={@auto_transforms}
        slide_id={@slide.id} highlights={@highlights} />
      <.show_images :if={@slide && @slide.images} images={@slide.images}
        transforms={Map.get(@slide.transforms || %{}, "", %{})} auto_transforms={@auto_transforms}
        slide_id={@slide.id} image_frames={@image_frames} />
      <div class="fixed z-9999 bottom-0 left-1/2 transform -translate-x-1/2 join">
        <.link :for={slide <- @lesson.slides}
          class={["join-item btn btn-xs btn-outline", slide.position == @slide_position && "btn-primary"]}
          patch={~p"/lessons/#{@lesson.id}/slides/#{slide.position}"}>{slide.position}</.link>
      </div>
      <div class="fixed z-9999 bottom-0 right-0">
        <.link class="btn btn-circle btn-outline" patch={~p"/lessons/#{@lesson.id}/slides/#{@slide_position-1}"}>&lt;</.link>
        <.link class="btn btn-circle btn-outline" patch={~p"/lessons/#{@lesson.id}/slides/#{@slide_position+1}"}>&gt;</.link>
      </div>
      <div class="fixed z-9999 bottom-0 left-0 flex flex-col">
        <.show_save_transforms :if={@slide && @slide.transforms} transforms_state={@transforms_state} transforms={@slide.transforms} />
        <.show_toggle_background_gestures toggle_scroll={@toggle_scroll} toggle_sentences={@toggle_sentences} toggle_images={@toggle_images} />
        <.show_toggle_gestures toggle_pan={@toggle_pan} toggle_zoom={@toggle_zoom} toggle_rotate={@toggle_rotate} />
        <.link class="btn btn-sm btn-outline kai" patch={~p"/lessons/#{@lesson.id}/edit"}>編輯</.link>
        <button class="btn btn-sm btn-outline kai" phx-hook="FullScreen" id="fullscreen">全屏</button>
      </div>
    </div>
    """
  end

  def handle_event("change-lesson", %{"lesson" => params}, socket) do
    {:noreply,
     socket
     |> update(:lesson_changes, &Map.put(&1, String.to_integer(Map.get(params, "id", "-1")), params))}
  end

  def handle_event("submit-lesson", %{"lesson" => %{"id" => _} = params}, socket) do
    id = String.to_integer(params["id"])
    Lesson |> Repo.get!(id) |> Lesson.changeset(params) |> Repo.update!
    {:noreply,
     socket
     |> assign(lessons: Lesson |> order_by([desc: :position]) |> Repo.all)
     |> update(:lesson_changes, &Map.delete(&1, id))}
  end

  def handle_event("submit-lesson", %{"lesson" => params}, socket) do
    {:ok, _} = Repo.transact(fn ->
      max_pos = Lesson |> Repo.aggregate(:max, :position)
      %Lesson{} |> Lesson.changeset(Map.put(params, "position", (max_pos || 0)+1)) |> Repo.insert
    end)
    {:noreply,
     socket
     |> assign(lessons: Lesson |> order_by([desc: :position]) |> Repo.all)
     |> update(:lesson_changes, &Map.delete(&1, -1))}
  end

  def handle_event("move-lesson", %{"lesson" => lesson_id}, socket) do
    {:ok, _} = Repo.transact(fn ->
      lesson = Lesson |> Repo.get!(String.to_integer(lesson_id))
      lesson_prev = Lesson |> where([l], l.position > ^lesson.position) |> first(:position) |> Repo.one!
      lesson |> Lesson.changeset(%{position: lesson_prev.position}) |> Repo.update!
      lesson_prev |> Lesson.changeset(%{position: lesson.position}) |> Repo.update
    end)
    {:noreply,
     socket
     |> assign(lessons: Lesson |> order_by([desc: :position]) |> Repo.all)}
  end

  def handle_event("change-slide", %{"slide" => params}, socket) do
    id = String.to_integer(Map.get(params, "id", "-1"))
    {:noreply,
     socket
     |> update(:slide_changes, &Map.put(&1, id, decode_transforms(params)))}
  end

  def handle_event("submit-slide", %{"slide" => %{"id" => _} = params}, socket) do
    id = String.to_integer(params["id"])
    lesson_id = String.to_integer(params["lesson_id"])
    slide = Slide |> Repo.get!(id) |> Slide.changeset(decode_transforms(params)) |> Repo.update!
    {:noreply,
     socket
     |> assign(lesson: Lesson |> preload(:slides) |> Repo.get!(lesson_id))
     |> update(:slide_changes, &Map.delete(&1, id))}
  end

  def handle_event("submit-slide", %{"slide" => params}, socket) do
    lesson_id = String.to_integer(params["lesson_id"])
    {:ok, _} = Repo.transact(fn ->
      max_pos = Slide |> where(lesson_id: ^lesson_id) |> Repo.aggregate(:max, :position)
      %Slide{} |> Slide.changeset(Map.put(decode_transforms(params), "position", (max_pos || 0)+1)) |> Repo.insert
    end)
    {:noreply,
     socket
     |> assign(lesson: Lesson |> preload(:slides) |> Repo.get!(lesson_id))
     |> update(:slide_changes, &Map.delete(&1, -1))}
  end

  def handle_event("move-slide", %{"slide" => slide_id}, socket) do
    {:ok, _} = Repo.transact(fn ->
      slide = Slide |> Repo.get!(String.to_integer(slide_id))
      slide_prev = Slide |> where(lesson_id: ^slide.lesson_id) |> where([s], s.position < ^slide.position) |> last(:position) |> Repo.one!
      slide |> Slide.changeset(%{position: slide_prev.position}) |> Repo.update!
      slide_prev |> Slide.changeset(%{position: slide.position}) |> Repo.update
    end)
    {:noreply,
     socket
     |> assign(lesson: Lesson |> preload(:slides) |> Repo.get!(socket.assigns.lesson.id))}
  end

  def handle_event("change-image", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("submit-image", _params, socket) do
    consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
      random_name = Ecto.UUID.generate() <> Path.extname(entry.client_name)
      uploads_path = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]
      dest = Path.join(uploads_path, random_name)
      File.cp!(path, dest)
    end)
    {:noreply,
     socket
     |> assign(progress: 0, upload_images: get_uploaded_images())}
  end

  def handle_event("toggle-scroll", _params, socket) do
    {:noreply, update(socket, :toggle_scroll, &(not &1))}
  end

  def handle_event("toggle-sentences", _params, socket) do
    {:noreply, update(socket, :toggle_sentences, &(not &1))}
  end

  def handle_event("toggle-images", _params, socket) do
    {:noreply, update(socket, :toggle_images, &(not &1))}
  end

  def handle_event("toggle-pan", _params, socket) do
    {:noreply, update(socket, :toggle_pan, &(not &1))}
  end

  def handle_event("toggle-zoom", _params, socket) do
    {:noreply, update(socket, :toggle_zoom, &(not &1))}
  end

  def handle_event("toggle-rotate", _params, socket) do
    {:noreply, update(socket, :toggle_rotate, &(not &1))}
  end

  def handle_event("save-transforms", %{"slot" => slot}, socket) do
    active_transforms = Map.get(socket.assigns.slide.transforms, "")
    transforms =
      if active_transforms do
        Map.put(socket.assigns.slide.transforms, slot, active_transforms)
      else
        Map.delete(socket.assigns.slide.transforms, slot)
      end
    slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    {:noreply,
     socket
     |> update(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)
     |> assign(transforms_state: :pending)}
  end

  def handle_event("save-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :save)}
  end

  def handle_event("apply-transforms", %{"slot" => slot}, socket) do
    slot_transforms = Map.get(socket.assigns.slide.transforms, slot)
    transforms = Map.put(socket.assigns.slide.transforms, "", slot_transforms)
    slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    {:noreply,
     socket
     |> assign(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)
     |> assign(transforms_state: :pending)}
  end

  def handle_event("apply-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :apply)}
  end

  def handle_event("clear-transforms", _params, socket) do
    transforms = Map.delete(socket.assigns.slide.transforms, "")
    slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    {:noreply,
     socket
     |> assign(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)}
  end

  def handle_event("cancel-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :pending)}
  end

  def handle_event("flip", %{"image" => "image-" <> i}, socket) do
    slide = socket.assigns.slide
    image = Enum.at(String.split(slide.images, "\n"), String.to_integer(i))
    frames = length(String.split(image, " "))
    image_frames = Map.update(socket.assigns.image_frames, "#{slide.id}-#{i}", rem(1, frames), &(rem(&1 + 1, frames)))
    {:noreply,
     socket
     |> assign(image_frames: image_frames)
     |> assign(focus_id: "image-" <> i)}
  end

  def handle_event("drag", drags, socket) do
    active_transforms = Map.get(socket.assigns.slide.transforms || %{}, "", socket.assigns.auto_transforms)
    new_active_transforms = Enum.reduce(drags, active_transforms, fn drag, m ->
      %{"item" => item_id, "x" => x, "y" => y, "z" => z, "size" => size} = drag
      Map.put(m, item_id, [x,y,z,size])
    end)
    transforms = Map.put(socket.assigns.slide.transforms || %{}, "", new_active_transforms)
    slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    # todo
    focus_id =
      if length(drags) == 1 do
        Map.get(Enum.at(drags, 0), "item")
      else
        nil
      end
    {:noreply,
     socket
     |> assign(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)
     |> assign(focus_id: focus_id)}
  end

  def handle_event("log", %{"msg" => msg}, socket) do
    IO.inspect(msg)
    {:noreply, socket}
  end

  def handle_event("toggle-highlight", %{"key" => key}, socket) do
    [_slide_id, i, j] = String.split(key, "-")
    slide = socket.assigns.slide
    sentence = Enum.at(String.split(slide.sentences, "\n"), String.to_integer(i))
    {belongs_here, acc} =
      Enum.reduce(Enum.with_index(graphemes(sentence)), {0, []}, fn {{grapheme, _deco}, k}, {belongs_here, acc} ->
        if belongs_here == 2 do
          {2, acc}
        else
          if is_ascii_letter_or_digit(grapheme) do
            {(if k == String.to_integer(j), do: 1, else: belongs_here), [k | acc]}
          else
            if belongs_here == 1 do
              {2, acc}
            else
              {0, []}
            end
          end
        end
      end)
    neighbours = if belongs_here == 0, do: [], else: acc
    highlight_count = Enum.count(neighbours, &MapSet.member?(socket.assigns.highlights, "#{slide.id}-#{i}-#{&1}"))
    highlights =
      if highlight_count >= 2 and highlight_count == length(neighbours) do
        MapSet.put(Enum.reduce(neighbours, socket.assigns.highlights, &MapSet.delete(&2, "#{slide.id}-#{i}-#{&1}")), key)
      else
        if highlight_count == 0 and length(neighbours) > 0 do
          Enum.reduce(neighbours, socket.assigns.highlights, &MapSet.put(&2, "#{slide.id}-#{i}-#{&1}"))
        else
          if MapSet.member?(socket.assigns.highlights, key) do
            MapSet.delete(socket.assigns.highlights, key)
          else
            MapSet.put(socket.assigns.highlights, key)
          end
        end
      end
    {:noreply, assign(socket, highlights: highlights)}
  end

  defp decode_transforms(params) do
    case Map.get(params, "transforms", "null") do
      "null" -> Map.delete(params, "transforms")
      transforms -> Jason.decode!(transforms)
    end
  end

  defp update_lesson_slide(lesson, slide) do
    slides = Enum.map(lesson.slides, fn s -> if s.id == slide.id, do: slide, else: s end)
    %{lesson | slides: slides}
  end

  defp get_uploaded_images() do
    uploads_folder = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]
    uploads_folder
    |> File.ls!
    |> Enum.filter(fn file ->
      ext = file |> Path.extname |> String.downcase
      ext in [".jpg", ".jpeg", ".png", ".gif", ".webp"]
    end)
    |> Enum.map(fn file ->
      path = Path.join(uploads_folder, file)
      {file, File.stat!(path).ctime}
    end)
    |> Enum.sort_by(fn {_file, ctime} -> ctime end, :desc)
    |> Enum.map(fn {file, _ctime} -> file end)
  end

  defp get_sentence_style(active_transforms, auto_transforms, id) do
    [x,y,z,px] = Map.get(active_transforms, id, Map.get(auto_transforms, id))
    "left:#{x}px;top:#{y}px;z-index:#{z};font-size:#{px}px"
  end

  defp get_image_style(active_transforms, auto_transforms, id) do
    [x,y,z,px] = Map.get(active_transforms, id, Map.get(auto_transforms, id))
    "left:#{x}px;top:#{y}px;z-index:#{z};width:#{px}px"
  end

  defp is_word?(s), do: String.length(s) < 3 or not String.contains?(s, [" ", ".", "。"])

  defp auto_transform(slide) do
    words_per_row = 4
    images_per_row = 4

    sentences = String.split(slide.sentences || "", "\n")
    images = String.split(slide.images || "", "\n")
    sentence_rows = Enum.sum_by(Enum.chunk_by(sentences, &is_word?/1), fn [e | rest] ->
      if is_word?(e) do
        Float.ceil(length([e | rest]) / words_per_row)
      else
        length([e | rest]) # one sentence per row
      end
    end)
    image_rows = Float.ceil(length(images) / images_per_row)
    dy = (720 - 100) / (sentence_rows + image_rows)
    a = auto_transform_sentences(sentences, dy, words_per_row)
    b = auto_transform_images(images, sentence_rows * dy, dy, images_per_row, length(sentences)+1)
    Map.merge(a, b)
  end

  defp auto_transform_sentences(sentences, dy, words_per_row) do
    dx = (1280 - 200) / words_per_row
    separate = Enum.concat(Enum.map(Enum.chunk_by(sentences, &is_word?/1), fn [e | rest] ->
      if is_word?(e) do
        Enum.chunk_every([e | rest], words_per_row)
      else
        Enum.map([e | rest], &([&1]))
      end
    end))
    l = Enum.concat(Enum.with_index(separate, fn [e | rest], y ->
      if is_word?(e) do
        Enum.with_index([e | rest], fn _word, x ->
          [100 + round(x * dx), round(y * dy), 0, 48]
        end)
      else
        [[100, round(y * dy), 0, 60]]
      end
    end))
    Map.new(Enum.with_index(l, fn [x,y,_,px], i -> {"sentence-#{i}", [x,y,1+i,px]} end))
  end

  defp auto_transform_images(images, begin_y, dy, images_per_row, begin_z) do
    dx = (1280 - 200) / images_per_row
    l = Enum.concat(Enum.with_index(Enum.chunk_every(images, images_per_row), fn row, y ->
      Enum.with_index(row, fn _image, x ->
        [100 + round(x * dx), round(begin_y + y * dy), 0, dx]
      end)
    end))
    Map.new(Enum.with_index(l, fn [x,y,_,px], i -> {"image-#{i}", [x,y,begin_z+i,px]} end))
  end

  defp graphemes(s) do
    parse_graphemes(String.graphemes(s), [])
  end

  defp parse_graphemes([], acc), do: Enum.reverse(acc)

  defp parse_graphemes(["_" | rest], acc) do
    {underlined, remaining} = collect_until(rest, "_", [])
    merged = Enum.join(underlined)
    parse_graphemes(remaining, [{merged, "underline"} | acc])
  end

  defp parse_graphemes(["(" | rest], acc) do
    {underlined, remaining} = collect_until(rest, ")", [])
    merged = Enum.join(underlined)
    parse_graphemes(remaining, [{merged, nil} | acc])
  end

  defp parse_graphemes(["|" | rest], acc) do
    parse_graphemes(rest, acc)
  end

  defp parse_graphemes([char | rest], acc) do
    if is_ascii_letter_or_digit(char) and false do
      {group, remaining} = collect_while([char | rest], &is_ascii_letter_or_digit/1, [])
      merged = Enum.join(group)
      parse_graphemes(remaining, [{merged, nil} | acc])
    else
      parse_graphemes(rest, [{char, nil} | acc])
    end
  end

  defp collect_until([], _target, collected), do: {Enum.reverse(collected), []}
  defp collect_until([target | rest], target, collected), do: {Enum.reverse(collected), rest}
  defp collect_until([char | rest], target, collected), do: collect_until(rest, target, [char | collected])

  defp collect_while([], _pred, collected), do: {Enum.reverse(collected), []}
  defp collect_while([char | rest], pred, collected) do
    if pred.(char) do
      collect_while(rest, pred, [char | collected])
    else
      {Enum.reverse(collected), [char | rest]}
    end
  end

  defp is_ascii_letter_or_digit(char) do
    char =~ ~r/^[A-Za-z0-9]$/
  end
end

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
     |> assign(draw_colors: [{"text-red-500", "oklch(63.7% 0.237 25.331)"},
                             {"text-orange-400", "oklch(75% 0.183 55.934)"},
                             {"text-yellow-300", "oklch(90.5% 0.182 98.111)"},
                             {"text-green-500", "oklch(72.3% 0.219 149.579)"},
                             {"text-blue-500", "oklch(62.3% 0.214 259.815)"},
                             {"text-purple-500", "oklch(62.7% 0.265 303.9)"}])
     |> allow_upload(:image,
                     accept: ~w(.jpg .jpeg .png .gif .webp .avif .svg),
                     max_file_size: 1_000_000_000,
                     max_entries: 20,
                     auto_upload: true,
                     progress: &handle_progress/3)}
  end

  defp handle_progress(:image, entry, socket) do
    if entry.done? do
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        random_name = entry.uuid <> Path.extname(entry.client_name)
        uploads_path = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]
        dest = Path.join(uploads_path, random_name)
        File.cp!(path, dest)
        {:ok, nil}
      end)
      {:noreply,
       socket
       |> assign(progresses: Map.delete(socket.assigns.progresses, entry.uuid))
       |> assign(uploaded_images: get_uploaded_images())}
    else
      {:noreply,
       socket
       |> assign(progresses: Map.put(socket.assigns.progresses, entry.uuid, entry.progress))}
    end
  end

  def handle_info(slide, socket) do
    {:noreply,
     socket
     |> update(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)}
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
     |> assign(progresses: %{}, uploaded_images: get_uploaded_images())}
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
    case {socket.assigns[:slide], slide} do
      {nil, nil} -> nil
      {prev_slide, nil} -> Phoenix.PubSub.unsubscribe(Mkaps.PubSub, "slide:#{prev_slide.id}")
      {nil, slide} -> Phoenix.PubSub.subscribe(Mkaps.PubSub, "slide:#{slide.id}")
      {prev_slide, slide} ->
        if prev_slide.id != slide.id do
          Phoenix.PubSub.unsubscribe(Mkaps.PubSub, "slide:#{prev_slide.id}")
          Phoenix.PubSub.subscribe(Mkaps.PubSub, "slide:#{slide.id}")
        end
    end
    {:noreply,
     socket
     |> assign(lesson: lesson)
     |> assign(slide: slide)
     |> assign(slide_position: position)
     |> assign(auto_transforms: slide && auto_transform(slide, "top-bottom"))
     |> assign(transforms_state: :pending)
     |> assign(focus_id: nil)
     |> assign(draw_color: nil)
     |> assign(burger: true)
     |> assign(knob: nil)
     |> assign(max_seek: nil)
     |> push_event("redraw", %{})}
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
        <button class="join-item btn btn-primary" type="submit" disabled={@form.source.changes == %{}}>
          {if @form[:id].value, do: "Save", else: "Create"}
        </button>
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
    <div id="idle-check" phx-hook="IdleDisconnect"></div>
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
      <button class="btn btn-primary" type="submit" disabled={@form.source.changes == %{}}>
        {if @form[:id].value, do: "Save", else: "Create"}
      </button>
      <div :if={@form[:id].value} class="join">
        <button class="join-item btn btn-secondary" type="button" phx-click="move-slide" phx-value-slide={@form[:id].value}>Move</button>
        <.link class="join-item btn btn-accent" patch={~p"/lessons/#{@form[:lesson_id].value}/slides/#{@form[:position].value}"}>Play</.link>
      </div>
      <div :if={@form[:images].value}>
        <img :for={image <- String.split(@form[:images].value, "\n")}
          class="h-24 w-auto inline m-1"
          src={Enum.at(String.split(image, " "), 0)} />
      </div>
      <textarea class={["textarea", Map.has_key?(@form.source.changes, :transforms) && "textarea-primary"]}
        name={@form[:transforms].name} placeholder="Transforms">{Jason.encode!(@form[:transforms].value || %{})}</textarea>
      <textarea class={["textarea", Map.has_key?(@form.source.changes, :avatars) && "textarea-primary"]}
        name={@form[:avatars].name} placeholder="Avatars">{Map.get(@form[:avatars].value || %{}, "names") || ""}</textarea>
    </.form>
    """
  end

  attr :lesson, Lesson, required: true
  attr :slide_changes, :map, required: true
  attr :progresses, :map, required: true
  attr :uploaded_images, :list, required: true
  defp edit(assigns) do
    ~H"""
    <div id="idle-check" phx-hook="IdleDisconnect"></div>
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
      <div :for={{_uuid, progress} <- @progresses} class="badge badge-primary">{progress}%</div>
    </form>
    <div>Click one of them to copy image link</div>
    <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
      <div :for={image <- @uploaded_images}
        class="flex flex-col items-center space-y-2"
        phx-hook="CopyOnClick" id={"image-#{image}"} data-copy-text={"/uploads/#{image}"}>
        <span>{image}</span>
        <img src={"/uploads/#{image}"} class="w-full max-w-xs max-h-64 object-contain" />
      </div>
    </div>
    """
  end

  attr :i, :integer, required: true
  attr :transforms, :map, required: true
  attr :auto_transforms, :map, required: true
  attr :slide_id, :integer, required: true
  attr :highlights, :map, required: true
  attr :groups, :list, required: true
  defp show_sentence(assigns) do
    ~H"""
    <div class={["absolute w-max max-w-[1080px] px-[0.4em] py-[0.1em]",
      "text-black leading-[1.1] kai",
      "mkaps-sentence mkaps-drag",
      is_plain_text?(@groups) && "rounded-lg bg-stone-100 shadow-sm/100"]}
      phx-hook="Touchable" id={"sentence-#{@i}"}
      style={get_sentence_style(@transforms, @auto_transforms, "sentence-#{@i}")}>
      <span :for={{grapheme_group, deco, j} <- @groups}
        class={["whitespace-nowrap",
          deco == "inline-block" && "inline-block",
          deco == "紅" && "px-[0.3em] py-[0.1em] inline-block rounded-full text-pink-900 bg-pink-400",
          deco == "橙" && "px-[0.3em] py-[0.1em] inline-block rounded-full text-orange-900 bg-orange-400",
          deco == "黃" && "px-[0.3em] py-[0.1em] inline-block rounded-full text-amber-900 bg-amber-400",
          deco == "綠" && "px-[0.3em] py-[0.1em] inline-block rounded-full text-green-900 bg-green-500",
          deco == "藍" && "px-[0.3em] py-[0.1em] inline-block rounded-full text-blue-900 bg-blue-400",
          deco == "紫" && "px-[0.3em] py-[0.1em] inline-block rounded-full text-purple-900 bg-purple-400",
          deco == "灰" && "px-[0.3em] py-[0.1em] inline-block rounded-full text-zinc-900 bg-zinc-400"]}>
        <%= if deco == "網" do %>
        <a class="link link-primary" draggable="false" target="_blank" href={Enum.join(grapheme_group)}>{Enum.join(grapheme_group)}</a>
        <% else %>
        <span :for={{grapheme, k} <- Enum.with_index(grapheme_group)}
          :if={grapheme != " "}
          phx-hook="Touchable" id={"#{@slide_id}-#{@i}-#{j+k}"}
          class={["inline-block mkaps-grapheme",
            "#{@slide_id}-#{@i}-#{j+k}" in @highlights && "text-violet-900 bg-violet-200",
            "#{@slide_id}-#{@i}-#{j+k-1}" not in @highlights && "rounded-l-md",
            "#{@slide_id}-#{@i}-#{j+k+1}" not in @highlights && "rounded-r-md",
            deco == "underline" && "underline underline-offset-[0.15em]"]}>
          {grapheme}
        </span>
        <% end %>
      </span>
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
    <.show_sentence :for={{sentence, i} <- Enum.with_index(String.split(@sentences, "\n"))}
      :if={sentence != ""} i={i}
      transforms={@transforms} auto_transforms={@auto_transforms}
      slide_id={@slide_id} highlights={@highlights} groups={with_grapheme_index(grapheme_groups(sentence))} />
    """
  end

  attr :images, :string, required: true
  attr :transforms, :map, required: true
  attr :auto_transforms, :map, required: true
  attr :slide_id, :integer, required: true
  attr :image_frames, :map, required: true
  defp show_images(assigns) do
    ~H"""
    <img :for={{image, i} <- Enum.with_index(String.split(@images, "\n"))}
      :if={image != ""}
      class="absolute h-auto shadow-sm/100 rounded-lg mkaps-image mkaps-drag"
      draggable="false"
      src={Enum.at(String.split(image, " "), Map.get(@image_frames, "#{@slide_id}-#{i}", 0))}
      phx-hook="Touchable" id={"image-#{i}"}
      style={get_image_style(@transforms, @auto_transforms, "image-#{i}")} />
    """
  end

  attr :avatars, :map, required: true
  attr :focus_id, :string, default: nil
  attr :transforms, :map, required: true
  attr :auto_transforms, :map, required: true
  defp show_avatars(assigns) do
    ~H"""
    <span :for={{name, i} <- Enum.with_index(String.split(Map.get(@avatars, "names", ""), "\n"))}
      :if={name != ""}
      class="absolute h-auto mkaps-avatar mkaps-drag"
      phx-hook="Touchable" id={"avatar-#{i}"}
      style={get_avatar_style(@transforms, @auto_transforms, "avatar-#{i}")}>
      <img class="w-full" draggable="false" src="/images/schoolbag.png"
        style={"filter:#{Map.get(Map.get(@avatars, "avatar-#{i}", %{}), "filter", "contrast(3) grayscale(1) brightness(4)")}" <>
          if @focus_id == "avatar-#{i}", do: " drop-shadow(0 0 10px #fff)", else: ""} />
      <span class="absolute bottom-[9%] left-[26%] -translate-x-1/2 rotate-14 text-black kai"
        style={"#{get_avatar_name_size(@transforms, @auto_transforms, "avatar-#{i}")};text-shadow: 0 0 4px white"}>{name}</span>
      <span class="absolute rotate-14"
        style={"#{get_avatar_badge_size(@transforms, @auto_transforms, "avatar-#{i}")};top:9%;left:19%;width:48%;text-shadow: 0 0 4px white"}>
        {Enum.join(Enum.reverse(Map.get(Map.get(@avatars, "avatar-#{i}", %{}), "badges", [])))}
      </span>
    </span>
    """
  end

  attr :avatars, :map, required: true
  attr :focus_id, :string, required: true
  defp show_avatar_ui(assigns) do
    ~H"""
    <div class="join pointer-events-auto">
      <button class="join-item btn btn-sm kai btn-outline" phx-click="add-badge" phx-value-badge="👍">👍</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="add-badge" phx-value-badge="⭐">⭐</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="add-badge" phx-value-badge="❤️">❤️</button>
      <button class="join-item btn btn-sm kai btn-outline"
        phx-click="delete-badge" disabled={Map.get(Map.get(@avatars, @focus_id, %{}), "badges", []) == []}>X</button>
    </div>
    <div class="join pointer-events-auto">
      <button class="join-item btn btn-sm kai btn-outline text-red-500" phx-click="choose-avatar-color" phx-value-filter="hue-rotate(345deg) brightness(99%)">⬤</button>
      <button class="join-item btn btn-sm kai btn-outline text-orange-400" phx-click="choose-avatar-color" phx-value-filter="hue-rotate(59deg) brightness(240%)">⬤</button>
      <button class="join-item btn btn-sm kai btn-outline text-yellow-300" phx-click="choose-avatar-color" phx-value-filter="hue-rotate(67deg) brightness(325%)">⬤</button>
      <button class="join-item btn btn-sm kai btn-outline text-green-500" phx-click="choose-avatar-color" phx-value-filter="hue-rotate(163deg) brightness(171%)">⬤</button>
      <button class="join-item btn btn-sm kai btn-outline text-blue-500" phx-click="choose-avatar-color" phx-value-filter="hue-rotate(204deg) brightness(142%)">⬤</button>
      <button class="join-item btn btn-sm kai btn-outline text-purple-500" phx-click="choose-avatar-color" phx-value-filter="hue-rotate(272deg) brightness(150%)">⬤</button>
      <button class="join-item btn btn-sm kai btn-outline text-white" phx-click="choose-avatar-color" phx-value-filter="contrast(3) grayscale(1) brightness(4)">⬤</button>
    </div>
    """
  end

  attr :draw_color, :string, required: true
  attr :draw_colors, :list, required: true
  defp show_draw(assigns) do
    ~H"""
    <div class="join tooltip tooltip-right pointer-events-auto" data-tip="啟用繪畫、復原、重做">
      <%= if @draw_color do %>
      <button :for={{css, oklch} <- @draw_colors}
        class={["join-item btn btn-sm btn-outline", css]}
        phx-click="choose-draw-color" phx-value-color={oklch}>{if @draw_color == oklch, do: "●", else: "○"}</button>
      <button class="join-item btn btn-sm btn-outline" phx-click="draw-undo">↶</button>
      <button class="join-item btn btn-sm btn-outline" phx-click="draw-redo">↷</button>
      <% else %>
      <button class="join-item btn btn-sm btn-outline text-red-500" phx-click="choose-draw-color" phx-value-color="oklch(63.7% 0.237 25.331)">○</button>
      <% end %>
    </div>
    """
  end

  attr :transforms_state, :atom, required: true
  attr :transforms, :map, required: true
  defp show_save_transforms(assigns) do
    ~H"""
    <div class="join tooltip tooltip-right pointer-events-auto" data-tip="存取物件位置表">
      <%= if @transforms_state == :pending do %>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="save-transforms">存</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="apply-transforms">用</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="preset-transforms">版</button>
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
      <%= if @transforms_state == :preset do %>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="cancel-transforms">取消</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="preset-transforms" phx-value-layout="left-right">左圖右字</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="preset-transforms" phx-value-layout="right-left">左字右圖</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="preset-transforms" phx-value-layout="top-bottom">上圖下字</button>
      <button class="join-item btn btn-sm kai btn-outline" phx-click="preset-transforms" phx-value-layout="bottom-top">上字下圖</button>
      <% end %>
    </div>
    """
  end

  attr :toggle_scroll, :boolean, required: true
  attr :toggle_sentences, :boolean, required: true
  attr :toggle_images, :boolean, required: true
  defp show_toggle_background_gestures(assigns) do
    ~H"""
    <div class="join tooltip tooltip-right pointer-events-auto" data-tip="輕觸背景捲動，或操控所有字/圖">
      <button class={"join-item btn btn-sm kai #{if @toggle_scroll, do: "btn-primary", else: "btn-outline"}"}
        phx-click="toggle-scroll">捲</button>
      <button class={"join-item btn btn-sm kai #{if @toggle_sentences, do: "btn-primary", else: "btn-outline"}"}
        phx-click="toggle-sentences">字</button>
      <button class={"join-item btn btn-sm kai #{if @toggle_images, do: "btn-primary", else: "btn-outline"}"}
        phx-click="toggle-images">圖</button>
    </div>
    """
  end

  attr :toggle_pan, :boolean, required: true
  attr :toggle_zoom, :boolean, required: true
  attr :toggle_rotate, :boolean, required: true
  defp show_toggle_gestures(assigns) do
    ~H"""
    <div class="join tooltip tooltip-right pointer-events-auto" data-tip="啟用輕觸動作移動、縮放、旋轉">
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
  attr :draw_color, :string, required: true
  attr :toggle_pan, :boolean, required: true
  attr :toggle_zoom, :boolean, required: true
  attr :toggle_rotate, :boolean, required: true
  attr :lesson, Lesson, required: true
  attr :slide, Slide, default: nil
  attr :slide_position, :integer, required: true
  attr :auto_transforms, :map, required: true
  attr :focus_id, :string, default: nil
  attr :burger, :boolean, required: true
  attr :max_seek, :integer, required: true
  attr :knob, :integer, required: true
  defp show_slide(assigns) do
    ~H"""
    <div id="idle-check" phx-hook="IdleDisconnect"></div>
    <div class={["w-[1280px] h-[720px] bg-[url(/images/background1.jpg)] bg-cover bg-center relative overflow-hidden select-none",
      @toggle_scroll && "mkaps-toggle-scroll",
      @toggle_sentences && "mkaps-toggle-sentences",
      @toggle_images && "mkaps-toggle-images",
      @toggle_pan && "mkaps-toggle-pan",
      @toggle_zoom && "mkaps-toggle-zoom",
      @toggle_rotate && "mkaps-toggle-rotate",
      not @toggle_scroll && "touch-none"]}
      phx-hook="Touchable" id="board">
      <div class="absolute size-full bg-zinc-800/90"></div>
      <canvas class="absolute size-full z-9999 pointer-events-none"
        id="static-canvas" width="3840" height="2160" style="image-rendering:pixelated"></canvas>
      <canvas class={["absolute size-full z-9999", !@draw_color && "pointer-events-none"]}
        phx-hook="Canvas" id="canvas" width="3840" height="2160" style="image-rendering:pixelated"
        data-color={@draw_color} data-slide-id={@slide && @slide.id}></canvas>
      <.show_sentences :if={@slide && @slide.sentences} sentences={@slide.sentences}
        transforms={Map.get(@slide.transforms || %{}, "", %{})} auto_transforms={@auto_transforms}
        slide_id={@slide.id} highlights={@highlights} />
      <.show_images :if={@slide && @slide.images} images={@slide.images}
        transforms={Map.get(@slide.transforms || %{}, "", %{})} auto_transforms={@auto_transforms}
        slide_id={@slide.id} image_frames={@image_frames} />
      <.show_avatars :if={@slide && @slide.avatars} avatars={@slide.avatars || %{}} focus_id={@focus_id}
        transforms={Map.get(@slide.transforms || %{}, "", %{})} auto_transforms={@auto_transforms} />
    </div>
    <div class="fixed z-9999 bottom-0 left-1/2 transform -translate-x-1/2 join select-none">
      <.link :for={slide <- @lesson.slides}
        class={["join-item btn btn-xs btn-outline", slide.position == @slide_position && "btn-primary"]}
        patch={~p"/lessons/#{@lesson.id}/slides/#{slide.position}"}>{slide.position}</.link>
    </div>
    <div class="fixed z-9999 bottom-0 right-0 select-none">
      <.link class="btn btn-circle btn-outline" patch={~p"/lessons/#{@lesson.id}/slides/#{@slide_position-1}"}>&lt;</.link>
      <.link class="btn btn-circle btn-outline" patch={~p"/lessons/#{@lesson.id}/slides/#{@slide_position+1}"}>&gt;</.link>
    </div>
    <%= if @burger do %>
    <div class="fixed z-9999 bottom-0 left-0 flex flex-col items-start select-none pointer-events-none">
      <.show_avatar_ui :if={@slide && String.starts_with?(@focus_id || "", "avatar-")} avatars={@slide.avatars} focus_id={@focus_id} />
      <.show_save_transforms :if={@slide && @slide.transforms} transforms_state={@transforms_state} transforms={@slide.transforms} />
      <.show_toggle_background_gestures :if={@slide} toggle_scroll={@toggle_scroll} toggle_sentences={@toggle_sentences} toggle_images={@toggle_images} />
      <div class="flex flex-col items-stretch">
        <div>
          <.show_toggle_gestures toggle_pan={@toggle_pan} toggle_zoom={@toggle_zoom} toggle_rotate={@toggle_rotate} />
          <.show_draw draw_color={@draw_color} draw_colors={@draw_colors} />
        </div>
        <%= if @draw_color && @max_seek do %>
        <form phx-change="seek">
          <input name="knob" type="range" min="0" max={@max_seek} value={@knob} class="range range-info w-full pointer-events-auto" />
        </form>
        <% end %>
      </div>
      <div class="pointer-events-auto">
        <button class="btn btn-sm btn-outline" phx-click="toggle-burger">☰</button>
        <.link class="btn btn-sm btn-outline kai" patch={~p"/lessons/#{@lesson.id}/edit"}>編輯</.link>
        <button class="btn btn-sm btn-outline kai" phx-hook="FullScreen" id="fullscreen">全屏</button>
      </div>
    </div>
    <% else %>
    <div class="fixed z-9999 bottom-0 left-0 flex flex-col select-none">
      <button class="btn btn-sm btn-outline" phx-click="toggle-burger">☰</button>
    </div>
    <% end %>
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
    avatars = if id == -1, do: nil, else: Enum.find(socket.assigns.lesson.slides, &(&1.id == id))
    decode_params = params |> decode_transforms |> decode_avatars(avatars || %{})
    {:noreply,
     socket
     |> update(:slide_changes, &Map.put(&1, id, decode_params))}
  end

  def handle_event("submit-slide", %{"slide" => %{"id" => _} = params}, socket) do
    id = String.to_integer(params["id"])
    lesson_id = String.to_integer(params["lesson_id"])
    avatars = Enum.find(socket.assigns.lesson.slides, &(&1.id == id)).avatars
    decode_params = params |> decode_transforms |> decode_avatars(avatars || %{})
    Slide |> Repo.get!(id) |> Slide.changeset(decode_params) |> Repo.update!
    {:noreply,
     socket
     |> assign(lesson: Lesson |> preload(:slides) |> Repo.get!(lesson_id))
     |> update(:slide_changes, &Map.delete(&1, id))}
  end

  def handle_event("submit-slide", %{"slide" => params}, socket) do
    lesson_id = String.to_integer(params["lesson_id"])
    {:ok, _} = Repo.transact(fn ->
      max_pos = Slide |> where(lesson_id: ^lesson_id) |> Repo.aggregate(:max, :position)
      decode_params = params |> decode_transforms |> decode_avatars(%{})
      %Slide{} |> Slide.changeset(Map.put(decode_params, "position", (max_pos || 0)+1)) |> Repo.insert
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
    {:noreply, socket}
  end

  def handle_event("toggle-scroll", _params, socket) do
    scroll = not socket.assigns.toggle_scroll
    sentences = not scroll and socket.assigns.toggle_sentences
    images = not scroll and socket.assigns.toggle_images
    pan = not scroll and socket.assigns.toggle_pan
    zoom = not scroll and socket.assigns.toggle_zoom
    rotate = not scroll and socket.assigns.toggle_rotate
    draw_color = if scroll, do: nil, else: socket.assigns.draw_color
    {:noreply,
     socket
     |> assign(toggle_scroll: scroll, toggle_sentences: sentences, toggle_images: images)
     |> assign(toggle_pan: pan, toggle_zoom: zoom, toggle_rotate: rotate)
     |> assign(draw_color: draw_color)}
  end

  def handle_event("toggle-sentences", _params, socket) do
    sentences = not socket.assigns.toggle_sentences
    scroll = not sentences and socket.assigns.toggle_scroll
    draw_color = if sentences, do: nil, else: socket.assigns.draw_color
    {:noreply,
     socket
     |> assign(toggle_scroll: scroll, toggle_sentences: sentences)
     |> assign(draw_color: draw_color)}
  end

  def handle_event("toggle-images", _params, socket) do
    images = not socket.assigns.toggle_images
    scroll = not images and socket.assigns.toggle_scroll
    draw_color = if images, do: nil, else: socket.assigns.draw_color
    {:noreply,
     socket
     |> assign(toggle_scroll: scroll, toggle_images: images)
     |> assign(draw_color: draw_color)}
  end

  def handle_event("toggle-pan", _params, socket) do
    pan = not socket.assigns.toggle_pan
    zoom = pan and socket.assigns.toggle_zoom
    rotate = zoom and socket.assigns.toggle_rotate
    {:noreply,
     socket
     |> assign(toggle_pan: pan, toggle_zoom: zoom, toggle_rotate: rotate)
     |> assign(toggle_scroll: false)
     |> assign(draw_color: nil)}
  end

  def handle_event("toggle-zoom", _params, socket) do
    zoom = not socket.assigns.toggle_zoom
    pan = zoom or socket.assigns.toggle_pan
    rotate = zoom and socket.assigns.toggle_rotate
    {:noreply,
     socket
     |> assign(toggle_pan: pan, toggle_zoom: zoom, toggle_rotate: rotate)
     |> assign(toggle_scroll: false)
     |> assign(draw_color: nil)}
  end

  def handle_event("toggle-rotate", _params, socket) do
    rotate = not socket.assigns.toggle_rotate
    zoom = rotate or socket.assigns.toggle_zoom
    pan = rotate or socket.assigns.toggle_pan
    {:noreply,
     socket
     |> assign(toggle_pan: pan, toggle_zoom: zoom, toggle_rotate: rotate)
     |> assign(toggle_scroll: false)
     |> assign(draw_color: nil)}
  end

  def handle_event("choose-draw-color", %{"color" => color}, socket) do
    {:noreply,
     socket
     |> assign(toggle_pan: false, toggle_zoom: false, toggle_rotate: false)
     |> assign(toggle_scroll: false, toggle_sentences: false, toggle_images: false)
     |> assign(draw_color: color)
     |> assign(focus_id: nil)}
  end

  def handle_event("draw-undo", _params, socket) do
    {:noreply, push_event(socket, "undo", %{})}
  end

  def handle_event("draw-redo", _params, socket) do
    {:noreply, push_event(socket, "redo", %{})}
  end

  def handle_event("seeked", %{"knob" => knob, "max_seek" => max_seek}, socket) do
    {:noreply, assign(socket, knob: knob, max_seek: max_seek)}
  end

  def handle_event("seeked", %{"knob" => knob}, socket) do
    {:noreply, assign(socket, knob: knob)}
  end

  def handle_event("seek", %{"knob" => knob}, socket) do
    {:noreply, push_event(socket, "seek", %{"knob" => knob})}
  end

  def handle_event("toggle-burger", _params, socket) do
    {:noreply, update(socket, :burger, &(not &1))}
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
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "slide:#{slide.id}", slide)
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
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "slide:#{slide.id}", slide)
    {:noreply,
     socket
     |> update(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)
     |> assign(transforms_state: :pending)}
  end

  def handle_event("apply-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :apply)}
  end

  def handle_event("preset-transforms", %{"layout" => layout}, socket) do
    preset_transforms = auto_transform(socket.assigns.slide, layout)
    transforms = Map.put(socket.assigns.slide.transforms, "", preset_transforms)
    slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "slide:#{slide.id}", slide)
    {:noreply,
     socket
     |> update(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)
     |> assign(transforms_state: :pending)}
  end

  def handle_event("preset-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :preset)}
  end

  # Legacy
  def handle_event("clear-transforms", _params, socket) do
    transforms = Map.delete(socket.assigns.slide.transforms, "")
    slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "slide:#{slide.id}", slide)
    {:noreply,
     socket
     |> update(:lesson, &update_lesson_slide(&1, slide))
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

  def handle_event("focus", %{"avatar" => avatar}, socket) do
    {:noreply, update(socket, :focus_id, &(if &1 == avatar, do: nil, else: avatar))}
  end

  def handle_event("drags", drags, socket) do
    active_transforms = Map.get(socket.assigns.slide.transforms || %{}, "", socket.assigns.auto_transforms)
    new_active_transforms = Enum.reduce(drags, active_transforms, fn drag, m ->
      %{"item" => item_id, "x" => x, "y" => y, "z" => z, "size" => size} = drag
      Map.put(m, item_id, [x,y,z,size])
    end)
    transforms = Map.put(socket.assigns.slide.transforms || %{}, "", new_active_transforms)
    slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    focus_id = Map.get(Enum.at(drags, 0), "item")
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "slide:#{slide.id}", slide)
    {:noreply,
     socket
     |> update(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)
     |> assign(focus_id: focus_id)}
  end

  def handle_event("commit", drags, socket) do
    active_transforms = Map.get(socket.assigns.slide.transforms || %{}, "", socket.assigns.auto_transforms)
    new_active_transforms = Enum.reduce(drags, active_transforms, fn drag, m ->
      %{"item" => item_id, "x" => x, "y" => y, "z" => z, "size" => size} = drag
      Map.put(m, item_id, [x,y,z,size])
    end)
    transforms = Map.put(socket.assigns.slide.transforms || %{}, "", new_active_transforms)
    slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "slide:#{slide.id}", slide)
    {:noreply, socket}
  end

  def handle_event("log", msg, socket) do
    IO.inspect(msg)
    {:noreply, socket}
  end

  def handle_event("toggle-highlight", %{"key" => key}, socket) do
    [slide_id, i, jk] = String.split(key, "-")
    sentence = Enum.at(String.split(socket.assigns.slide.sentences, "\n"), String.to_integer(i))
    {group, _deco, j} = Enum.find(with_grapheme_index(grapheme_groups(sentence)), fn {group,_,j} -> String.to_integer(jk) < j+length(group) end)
    indices = 0..(length(group)-1)
    highlight_count = Enum.count(indices, fn k -> "#{slide_id}-#{i}-#{j+k}" in socket.assigns.highlights end)
    highlights =
      if highlight_count >= 2 and highlight_count == length(group) do
        MapSet.put(Enum.reduce(indices, socket.assigns.highlights, &MapSet.delete(&2, "#{slide_id}-#{i}-#{j+&1}")), key)
      else
        if highlight_count == 0 do
          Enum.reduce(indices, socket.assigns.highlights, &MapSet.put(&2, "#{slide_id}-#{i}-#{j+&1}"))
        else
          if key in socket.assigns.highlights do
            MapSet.delete(socket.assigns.highlights, key)
          else
            MapSet.put(socket.assigns.highlights, key)
          end
        end
      end
    {:noreply,
     socket
     |> assign(highlights: highlights)
     |> assign(focus_id: "sentence-#{i}")}
  end

  def handle_event("add-badge", %{"badge" => badge}, socket) do
    avatar = Map.get(socket.assigns.slide.avatars || %{}, socket.assigns.focus_id)
    new_avatar = Map.update(avatar || %{}, "badges", [badge], &([badge | &1]))
    avatars = Map.put(socket.assigns.slide.avatars || %{}, socket.assigns.focus_id, new_avatar)
    slide = socket.assigns.slide |> Slide.changeset(%{avatars: avatars}) |> Repo.update!
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "slide:#{slide.id}", slide)
    {:noreply,
     socket
     |> update(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)}
  end

  def handle_event("delete-badge", _params, socket) do
    avatar = Map.get(socket.assigns.slide.avatars || %{}, socket.assigns.focus_id)
    new_avatar = Map.update(avatar || %{}, "badges", [], fn badges ->
      case badges do
        [_badge | rest] -> rest
        [] -> []
      end
    end)
    avatars = Map.put(socket.assigns.slide.avatars || %{}, socket.assigns.focus_id, new_avatar)
    slide = socket.assigns.slide |> Slide.changeset(%{avatars: avatars}) |> Repo.update!
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "slide:#{slide.id}", slide)
    {:noreply,
     socket
     |> update(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)}
  end

  def handle_event("choose-avatar-color", %{"filter" => filter}, socket) do
    avatar = Map.get(socket.assigns.slide.avatars || %{}, socket.assigns.focus_id)
    new_avatar = Map.put(avatar || %{}, "filter", filter)
    avatars = Map.put(socket.assigns.slide.avatars || %{}, socket.assigns.focus_id, new_avatar)
    slide = socket.assigns.slide |> Slide.changeset(%{avatars: avatars}) |> Repo.update!
    Phoenix.PubSub.broadcast_from(Mkaps.PubSub, self(), "slide:#{slide.id}", slide)
    {:noreply,
     socket
     |> update(:lesson, &update_lesson_slide(&1, slide))
     |> assign(slide: slide)}
  end

  def handle_event("idle_disconnect", _params, socket) do
    {:noreply, push_navigate(socket, to: "/idle.html")}
  end

  defp decode_transforms(params) do
    case Map.get(params, "transforms", "") do
      "" -> Map.delete(params, "transforms")
      transforms -> %{params | "transforms" => Jason.decode!(transforms)}
    end
  end

  defp decode_avatars(params, avatars) do
    names = Map.get(params, "avatars")
    %{params | "avatars" => Map.put(avatars, "names", names)}
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

  defp get_avatar_style(active_transforms, auto_transforms, id) do
    [x,y,z,px] = Map.get(active_transforms, id, Map.get(auto_transforms, id))
    "left:#{x}px;top:#{y}px;z-index:#{z};width:#{px}px"
  end

  defp get_avatar_name_size(active_transforms, auto_transforms, id) do
    [_,_,_,px] = Map.get(active_transforms, id, Map.get(auto_transforms, id))
    "font-size:#{trunc(px / 8)}px"
  end

  defp get_avatar_badge_size(active_transforms, auto_transforms, id) do
    [_,_,_,px] = Map.get(active_transforms, id, Map.get(auto_transforms, id))
    "font-size:#{trunc(px / 12)}px"
  end

  defp is_plain_text?([{_groups, nil, _j}]), do: true
  defp is_plain_text?([{_groups, "underline", _j}]), do: true
  defp is_plain_text?([{_groups, "網", _j}]), do: true
  defp is_plain_text?([{_groups, _deco, _j}]), do: false
  defp is_plain_text?(_groups), do: true
  defp is_word?(s), do: String.length(s) <= 4 or not String.contains?(s, [" ", ".", "?","。","？"])

  defp vertical_per_row(n) do
    cond do
      n <= 3 -> 3
      n <= 5 -> n
      n <= 10 -> Float.ceil(n / 2)
      n <= 18 -> Float.ceil(n / 3)
      n <= 28 -> Float.ceil(n / 4)
      true -> Float.ceil(n / 5)
    end
    |> round
  end

  defp horizontal_per_row(n) do
    cond do
      n <= 3 -> 1
      n <= 10 -> 2
      n <= 18 -> 3
      n <= 28 -> 4
      true -> 5
    end
    |> round
  end

  defp auto_transform(slide, layout) do
    case layout do
      "top-bottom" -> auto_transform_vertical(slide, layout)
      "bottom-top" -> auto_transform_vertical(slide, layout)
      "left-right" -> auto_transform_horizontal(slide, layout)
      "right-left" -> auto_transform_horizontal(slide, layout)
    end
  end

  defp ignore_empty([""]), do: []
  defp ignore_empty(s), do: s

  defp auto_transform_vertical(slide, layout) do
    sentences = ignore_empty(String.split(slide.sentences || "", "\n"))
    images = ignore_empty(String.split(slide.images || "", "\n"))
    avatars = ignore_empty(String.split(Map.get(slide.avatars || %{}, "names", ""), "\n"))

    words_per_row = 5
    images_per_row = vertical_per_row(length(images))
    avatars_per_row = vertical_per_row(length(avatars))

    sentence_rows = Enum.sum_by(Enum.chunk_by(sentences, &is_word?/1), fn [e | rest] ->
      if is_word?(e) do
        Float.ceil(length([e | rest]) / words_per_row)
      else
        length([e | rest]) # one sentence per row
      end
    end)
    image_rows = Float.ceil(length(images) / images_per_row)
    avatar_rows = Float.ceil(length(avatars) / avatars_per_row)

    factor = (1280 - 200) / images_per_row / 100
    dy = Enum.min([100, (720 - 100) / (sentence_rows + image_rows * factor + avatar_rows)])
    case layout do
      "top-bottom" ->
        %{}
        |> Map.merge(auto_transform_images(images, images_per_row, image_rows, 1, {100, 0}, {1280 - 200, image_rows * factor * dy}))
        |> Map.merge(auto_transform_sentences(sentences, words_per_row, sentence_rows, length(images)+1, {100, image_rows * factor * dy}, {1280 - 200, sentence_rows * dy}))
        |> Map.merge(auto_transform_avatars(avatars, avatars_per_row, avatar_rows, length(sentences)+length(images)+1, {100, (sentence_rows + image_rows * factor) * dy}, {1280 - 200, avatar_rows * dy}))
      "bottom-top" ->
        %{}
        |> Map.merge(auto_transform_sentences(sentences, words_per_row, sentence_rows, 1, {100, 0}, {1280 - 200, sentence_rows * dy}))
        |> Map.merge(auto_transform_images(images, images_per_row, image_rows, length(sentences)+1, {100, sentence_rows * dy}, {1280 - 200, image_rows * factor * dy}))
        |> Map.merge(auto_transform_avatars(avatars, avatars_per_row, avatar_rows, length(sentences)+length(images)+1, {100, (sentence_rows + image_rows * factor) * dy}, {1280 - 200, avatar_rows * dy}))
    end
  end

  defp auto_transform_horizontal(slide, layout) do
    sentences = ignore_empty(String.split(slide.sentences || "", "\n"))
    images = ignore_empty(String.split(slide.images || "", "\n"))
    avatars = ignore_empty(String.split(Map.get(slide.avatars || %{}, "names", ""), "\n"))

    words_per_row = 3
    images_per_row = horizontal_per_row(length(images))
    avatars_per_row = horizontal_per_row(length(avatars))

    sentence_rows = Enum.sum_by(Enum.chunk_by(sentences, &is_word?/1), fn [e | rest] ->
      if is_word?(e) do
        Float.ceil(length([e | rest]) / words_per_row)
      else
        length([e | rest]) # one sentence per row
      end
    end)
    image_rows = Float.ceil(length(images) / images_per_row)
    avatar_rows = Float.ceil(length(avatars) / avatars_per_row)

    sentences_factor = if length(sentences) == 0, do: 0, else: 400
    images_factor = if length(images) == 0, do: 0, else: 200 * images_per_row
    avatars_factor = if length(avatars) == 0, do: 0, else: 100 * avatars_per_row
    sum_factors = sentences_factor + images_factor + avatars_factor
    sentences_wh = {1280 / sum_factors * sentences_factor, 720 - 100}
    images_wh = {1280 / sum_factors * images_factor, 720 - 100}
    avatars_wh = {1280 / sum_factors * avatars_factor, 720 - 100}
    case layout do
      "left-right" ->
        %{}
        |> Map.merge(auto_transform_images(images, images_per_row, image_rows, 1, {0, 0}, images_wh))
        |> Map.merge(auto_transform_sentences(sentences, words_per_row, sentence_rows, length(images)+1, {1280 / sum_factors * images_factor, 0}, sentences_wh))
        |> Map.merge(auto_transform_avatars(avatars, avatars_per_row, avatar_rows, length(sentences)+length(images)+1, {1280 / sum_factors * (images_factor + sentences_factor), 0}, avatars_wh))
      "right-left" ->
        %{}
        |> Map.merge(auto_transform_sentences(sentences, words_per_row, sentence_rows, 1, {0, 0}, sentences_wh))
        |> Map.merge(auto_transform_images(images, images_per_row, image_rows, length(sentences)+1, {1280 / sum_factors * sentences_factor, 0}, images_wh))
        |> Map.merge(auto_transform_avatars(avatars, avatars_per_row, avatar_rows, length(sentences)+length(images)+1, {1280 / sum_factors * (images_factor + sentences_factor), 0}, avatars_wh))
    end
  end

  defp auto_transform_sentences([], _, _, _, _, _), do: %{}
  defp auto_transform_sentences(sentences, words_per_row, sentence_rows, begin_z, {begin_x, begin_y}, {w, h}) do
    {dx, dy} = {w / words_per_row, h / sentence_rows}
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
          [round(begin_x + x * dx), round(begin_y + y * dy), 0, 48]
        end)
      else
        [[begin_x, round(begin_y + y * dy), 0, 60]]
      end
    end))
    Map.new(Enum.with_index(l, fn [x,y,_,px], i -> {"sentence-#{i}", [x,y,begin_z+i,px]} end))
  end

  defp auto_transform_images([], _, _, _, _, _), do: %{}
  defp auto_transform_images(images, images_per_row, image_rows, begin_z, {begin_x, begin_y}, {w, h}) do
    {dx, dy} = {w / images_per_row, h / image_rows}
    l = Enum.concat(Enum.with_index(Enum.chunk_every(images, images_per_row), fn row, y ->
      Enum.with_index(row, fn _image, x ->
        [round(begin_x + x * dx), round(begin_y + y * dy), 0, dx]
      end)
    end))
    Map.new(Enum.with_index(l, fn [x,y,_,px], i -> {"image-#{i}", [x,y,begin_z+i,px]} end))
  end

  defp auto_transform_avatars([], _, _, _, _, _), do: %{}
  defp auto_transform_avatars(avatars, avatars_per_row, avatar_rows, begin_z, {begin_x, begin_y}, {w, h}) do
    {dx, dy} = {w / avatars_per_row, h / avatar_rows}
    l = Enum.concat(Enum.with_index(Enum.chunk_every(avatars, avatars_per_row), fn row, y ->
      Enum.with_index(row, fn _avatar, x ->
        [round(begin_x + x * dx), round(begin_y + y * dy), 0, dx]
      end)
    end))
    Map.new(Enum.with_index(l, fn [x,y,_,px], i -> {"avatar-#{i}", [x,y,begin_z+i,px]} end))
  end

  defp with_grapheme_index(s) do
    s
    |> Enum.reduce([], fn {group, deco}, list ->
      case list do
        [] -> [{group, deco, 0}]
        [{prev_group, prev_deco, i} | rest] -> [{group, deco, i + length(prev_group)}, {prev_group, prev_deco, i} | rest]
      end
    end)
    |> Enum.reverse
  end

  defp grapheme_groups(s) do
    parse_grapheme_groups(String.graphemes(s), [])
  end

  defp parse_grapheme_groups([], acc), do: Enum.reverse(acc)

  defp parse_grapheme_groups(["_" | rest], acc) do
    {group, remaining} = collect_until(rest, "_", [])
    parse_grapheme_groups(remaining, [{group, "underline"} | acc])
  end

  defp parse_grapheme_groups(["[" , deco, ":" | rest], acc) do
    {group, remaining} = collect_until(rest, "]", [])
    parse_grapheme_groups(remaining, [{group, deco} | acc])
  end

  defp parse_grapheme_groups([char , "。" | rest], acc) do
    parse_grapheme_groups(rest, [{[char, "。"], "inline-block"} | acc])
  end

  defp parse_grapheme_groups([char , "，" | rest], acc) do
    parse_grapheme_groups(rest, [{[char, "，"], "inline-block"} | acc])
  end

  defp parse_grapheme_groups([char , "？" | rest], acc) do
    parse_grapheme_groups(rest, [{[char, "？"], "inline-block"} | acc])
  end

  defp parse_grapheme_groups([char | rest], acc) do
    if is_ascii_letter_or_digit(char) do
      {group, remaining} = collect_while([char | rest], &is_ascii_letter_or_digit/1, [])
      parse_grapheme_groups(remaining, [{group, nil} | acc])
    else
      parse_grapheme_groups(rest, [{[char], "inline-block"} | acc])
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
    char =~ ~r/^[A-Za-z0-9,\."']$/
  end
end

defmodule MkapsWeb.BoardLive do
  use MkapsWeb, :live_view
  import Ecto.Query, only: [order_by: 2, preload: 2, where: 2, where: 3, last: 2]
  alias Mkaps.Lesson
  alias Mkaps.Slide
  alias Mkaps.Repo

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(highlights: MapSet.new())
     |> assign(toggle_sentences: false, toggle_images: false)
     |> assign(transforms_state: :pending)
     |> assign(toggle_pan: true, toggle_zoom: false, toggle_rotate: false)
     |> assign(focus_id: nil)
     |> allow_upload(:image,
     accept: :any,
     max_file_size: 1_000_000_000,
     progress: fn :image, entry, socket -> {:noreply, assign(socket, progress: entry.progress)} end)}
  end

  def handle_params(%{"lesson_id" => lesson_id, "slide_position" => slide_position}, _uri, socket) do
    lesson = Lesson |> preload(:slides) |> Repo.get!(String.to_integer(lesson_id))
    position = String.to_integer(slide_position)
    {:noreply,
     socket
     |> assign(lesson: lesson)
     |> assign(slide: Enum.find(lesson.slides, &(&1.position == position)))
     |> assign(slide_position: position)}
  end

  def handle_params(%{"lesson_id" => lesson_id}, _uri, socket) do
    images = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]
    |> File.ls!
    |> Enum.filter(fn file ->
      ext = file |> Path.extname |> String.downcase
      ext in [".jpg", ".jpeg", ".png", ".gif", ".webp"]
    end)
    {:noreply,
     socket
     |> assign(lesson: Lesson |> preload(:slides) |> Repo.get!(String.to_integer(lesson_id)))
     |> assign(pending_saves: MapSet.new())
     |> assign(progress: 0, images: images)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(lessons: Lesson |> order_by(:position) |> Repo.all)
     |> assign(pending_saves: MapSet.new())}
  end

  def handle_event("change-lesson", %{"lesson" => lesson_id}, socket) do
    {:noreply,
     socket
     |> assign(pending_saves: MapSet.put(socket.assigns.pending_saves, "lesson-#{lesson_id}"))}
  end

  def handle_event("move-lesson", %{"lesson" => lesson_id}, socket) do
    {:ok, _} = Repo.transact(fn ->
      lesson = Lesson |> Repo.get!(String.to_integer(lesson_id))
      lesson_prev = Lesson |> where([l], l.position < ^lesson.position) |> last(:position) |> Repo.one!
      lesson |> Lesson.changeset(%{position: lesson_prev.position}) |> Repo.update!
      lesson_prev |> Lesson.changeset(%{position: lesson.position}) |> Repo.update!
      {:ok, nil}
    end)
    {:noreply,
     socket
     |> assign(lessons: Lesson |> order_by(:position) |> Repo.all)}
  end

  def handle_event("create-lesson", %{"name" => name}, socket) do
    max_pos = Lesson |> Repo.aggregate(:max, :position)
    %Lesson{} |> Lesson.changeset(%{name: name, position: max_pos+1}) |> Repo.insert!
    {:noreply,
     socket
     |> assign(lessons: Lesson |> order_by(:position) |> Repo.all)
     |> assign(pending_saves: MapSet.delete(socket.assigns.pending_saves, "lesson-create"))}
  end

  def handle_event("save-lesson", %{"lesson" => lesson_id, "name" => name}, socket) do
    lesson = Lesson |> Repo.get!(String.to_integer(lesson_id))
    lesson |> Lesson.changeset(%{name: name}) |> Repo.update!
    {:noreply,
     socket
     |> assign(lessons: Lesson |> order_by(:position) |> Repo.all)
     |> assign(pending_saves: MapSet.delete(socket.assigns.pending_saves, "lesson-#{lesson_id}"))}
  end

  def handle_event("change-slide", %{"slide" => slide_id}, socket) do
    {:noreply,
     socket
     |> assign(pending_saves: MapSet.put(socket.assigns.pending_saves, "slide-#{slide_id}"))}
  end

  def handle_event("move-slide", %{"slide" => slide_id}, socket) do
    {:ok, _} = Repo.transact(fn ->
      slide = Slide |> Repo.get!(String.to_integer(slide_id))
      slide_prev = Slide |> where(lesson_id: ^slide.lesson_id) |> where([s], s.position < ^slide.position) |> last(:position) |> Repo.one!
      slide |> Slide.changeset(%{position: slide_prev.position}) |> Repo.update!
      slide_prev |> Slide.changeset(%{position: slide.position}) |> Repo.update!
      {:ok, nil}
    end)
    {:noreply,
     socket
     |> assign(lesson: Lesson |> preload(:slides) |> Repo.get!(socket.assigns.lesson.id))}
  end

  def handle_event("create-slide", %{"sentences" => sentences, "images" => images}, socket) do
    lesson_id = socket.assigns.lesson.id
    max_pos = Slide |> where(lesson_id: ^lesson_id) |> Repo.aggregate(:max, :position)
    %Slide{} |> Slide.changeset(%{sentences: sentences, images: images, position: (max_pos || 0)+1, lesson_id: lesson_id}) |> Repo.insert!
    {:noreply,
     socket
     |> assign(lesson: Lesson |> preload(:slides) |> Repo.get!(lesson_id))
     |> assign(pending_saves: MapSet.delete(socket.assigns.pending_saves, "slide-create"))}
  end

  def handle_event("save-slide", %{"slide" => slide_id, "sentences" => sentences, "images" => images}, socket) do
    slide = Slide |> Repo.get!(String.to_integer(slide_id))
    slide |> Slide.changeset(%{sentences: sentences, images: images}) |> Repo.update!
    {:noreply,
     socket
     |> assign(lesson: Lesson |> preload(:slides) |> Repo.get!(slide.lesson_id))
     |> assign(pending_saves: MapSet.delete(socket.assigns.pending_saves, "slide-#{slide_id}"))}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save-image", _params, socket) do
    consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
      random_name = Ecto.UUID.generate() <> Path.extname(entry.client_name)
      uploads_path = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]
      dest = Path.join(uploads_path, random_name)
      File.cp!(path, dest)
      {:ok, nil}
    end)
    {:noreply, socket}
  end

  def handle_event("toggle-sentences", _params, socket) do
    {:noreply, assign(socket, toggle_sentences: !socket.assigns.toggle_sentences)}
  end

  def handle_event("toggle-images", _params, socket) do
    {:noreply, assign(socket, toggle_images: !socket.assigns.toggle_images)}
  end

  def handle_event("toggle-pan", _params, socket) do
    {:noreply, assign(socket, toggle_pan: !socket.assigns.toggle_pan)}
  end

  def handle_event("toggle-zoom", _params, socket) do
    {:noreply, assign(socket, toggle_zoom: !socket.assigns.toggle_zoom)}
  end

  def handle_event("toggle-rotate", _params, socket) do
    {:noreply, assign(socket, toggle_rotate: !socket.assigns.toggle_rotate)}
  end

  def handle_event("save-transforms", %{"slot" => slot}, socket) do
    active_transforms = Map.get(socket.assigns.slide.transforms || %{}, "")
    transforms = if active_transforms == nil do
      Map.delete(socket.assigns.slide.transforms || %{}, slot)
    else
      Map.put(socket.assigns.slide.transforms || %{}, slot, active_transforms)
    end
    socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    {:noreply,
     socket
     |> assign(transforms_state: :pending)
     |> assign(slide: Slide |> Repo.get!(socket.assigns.slide.id))}
  end

  def handle_event("save-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :save)}
  end

  def handle_event("apply-transforms", %{"slot" => slot}, socket) do
    slot_transforms = Map.get(socket.assigns.slide.transforms || %{}, slot)
    transforms = Map.put(socket.assigns.slide.transforms || %{}, "", slot_transforms)
    socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    {:noreply,
     socket
     |> assign(transforms_state: :pending)
     |> assign(slide: Slide |> Repo.get!(socket.assigns.slide.id))}
  end

  def handle_event("apply-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :apply)}
  end

  def handle_event("clear-transforms", _params, socket) do
    transforms = Map.delete(socket.assigns.slide.transforms || %{}, "")
    socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    {:noreply,
     socket
     |> assign(slide: Slide |> Repo.get!(socket.assigns.slide.id))}
  end

  def handle_event("cancel-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :pending)}
  end

  def handle_event("drag", %{"item" => item_id, "x" => x, "y" => y, "z" => z, "size" => size}, socket) do
    active_transforms = Map.get(socket.assigns.slide.transforms || %{}, "", %{})
    new_active_transforms = Map.put(active_transforms, item_id, [x,y,z,size])
    transforms = Map.put(socket.assigns.slide.transforms || %{}, "", new_active_transforms)
    socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    {:noreply,
     socket
     |> assign(focus_id: item_id)
     |> assign(slide: Slide |> Repo.get!(socket.assigns.slide.id))}
  end

  def handle_event("hue-left", _params, socket) do
    slide = socket.assigns.slide
    focus_id = socket.assigns.focus_id
    hue = get_avatar_hue(slide, focus_id)
    new_socket = if hue != nil do
      "image-" <> i = focus_id
      "avatar-" <> name = Enum.at(String.split(slide.images, "\n"), String.to_integer(i))
      avatar = Map.get(slide.avatars || %{}, name)
      new_avatar = if hue == 0 do
        Map.put(avatar || %{}, "hue", 330)
      else
        Map.put(avatar || %{}, "hue", hue - 30)
      end
      avatars = Map.put(slide.avatars || %{}, name, new_avatar)
      slide |> Slide.changeset(%{avatars: avatars}) |> Repo.update!
      assign(socket, slide: Slide |> Repo.get!(slide.id))
    else
      socket
    end
    {:noreply, new_socket}
  end

  def handle_event("hue-right", _params, socket) do
    slide = socket.assigns.slide
    focus_id = socket.assigns.focus_id
    hue = get_avatar_hue(slide, focus_id)
    new_socket = if hue != nil do
      "image-" <> i = focus_id
      "avatar-" <> name = Enum.at(String.split(slide.images, "\n"), String.to_integer(i))
      avatar = Map.get(slide.avatars || %{}, name)
      new_avatar = if hue == 330 do
        Map.put(avatar || %{}, "hue", 0)
      else
        Map.put(avatar || %{}, "hue", hue + 30)
      end
      avatars = Map.put(slide.avatars || %{}, name, new_avatar)
      slide |> Slide.changeset(%{avatars: avatars}) |> Repo.update!
      assign(socket, slide: Slide |> Repo.get!(slide.id))
    else
      socket
    end
    {:noreply, new_socket}
  end

  def handle_event("log", %{"msg" => msg}, socket) do
    IO.inspect(msg)
    {:noreply, socket}
  end

  def handle_event("toggle-highlight", %{"key" => key}, socket) do
    [_slide_id, i, j] = String.split(key, "-")
    slide = socket.assigns.slide
    sentence = Enum.at(String.split(slide.sentences, "\n"), String.to_integer(i))
    {belongs_here, acc} = Enum.reduce(Enum.with_index(graphemes(sentence)), {0, []}, fn {{grapheme, _deco}, k}, {belongs_here, acc} ->
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
    if highlight_count > 0 and highlight_count == length(neighbours) do
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

  defp get_sentence_style(active_transforms, item_id) do
    [x,y,z,px] = Map.get(active_transforms || %{}, item_id, [0,0,0,72])
    "left:#{x}px;top:#{y}px;z-index:#{z};font-size:#{px}px"
  end

  defp get_image_style(active_transforms, item_id) do
    [x,y,z,px] = Map.get(active_transforms || %{}, item_id, [0,0,0,200])
    "left:#{x}px;top:#{y}px;z-index:#{z};width:#{px}px"
  end

  defp get_avatar_name_style(active_transforms, item_id) do
    [_,_,_,px] = Map.get(active_transforms || %{}, item_id, [0,0,0,200])
    "font-size:#{round(px / 8)}px"
  end

  defp get_avatar_hue(slide, focus_id) do
    if slide && slide.images && focus_id && String.starts_with?(focus_id, "image-") do
      "image-" <> i = focus_id
      text = Enum.at(String.split(slide.images, "\n"), String.to_integer(i))
      if String.starts_with?(text, "avatar-") do
        "avatar-" <> name = text
        avatar = Map.get(slide.avatars || %{}, name)
        Map.get(avatar || %{}, "hue", 0)
      else
        nil
      end
    else
      nil
    end
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

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
     |> assign(toggle_scroll: true, toggle_sentences: false, toggle_images: false)
     |> assign(transforms_state: :pending)
     |> assign(toggle_pan: true, toggle_zoom: false, toggle_rotate: false)
     |> assign(focus_id: nil)
     |> assign(image_frames: %{})
     |> assign(lesson: nil)
     |> allow_upload(:image,
     accept: :any,
     max_file_size: 1_000_000_000,
     progress: fn :image, entry, socket -> {:noreply, assign(socket, progress: entry.progress)} end)}
  end

  def handle_params(%{"lesson_id" => lesson_id, "slide_position" => slide_position}, _uri, socket) do
    position = String.to_integer(slide_position)
    lesson = socket.assigns.lesson ||
      Lesson |> preload(:slides) |> Repo.get!(String.to_integer(lesson_id))
    slide = Enum.find(lesson.slides, &(&1.position == position))
    {:noreply,
     socket
     |> assign(lesson: lesson)
     |> assign(slide: slide)
     |> assign(auto_transforms: auto_transform(slide))
     |> assign(slide_position: position)}
  end

  def handle_params(%{"lesson_id" => lesson_id}, _uri, socket) do
    folder = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]

    images = folder
    |> File.ls!
    |> Enum.filter(fn file ->
      ext = file |> Path.extname |> String.downcase
      ext in [".jpg", ".jpeg", ".png", ".gif", ".webp"]
    end)
    |> Enum.map(fn file ->
      path = Path.join(folder, file)
      {file, File.stat!(path).ctime}
    end)
    |> Enum.sort_by(fn {_file, ctime} -> ctime end, :desc)
    |> Enum.map(fn {file, _ctime} -> file end)

    {:noreply,
     socket
     |> assign(lesson: Lesson |> preload(:slides) |> Repo.get!(String.to_integer(lesson_id)))
     |> assign(pending_saves: MapSet.new())
     |> assign(progress: 0, upload_images: images)}
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

    folder = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]

    images = folder
    |> File.ls!
    |> Enum.filter(fn file ->
      ext = file |> Path.extname |> String.downcase
      ext in [".jpg", ".jpeg", ".png", ".gif", ".webp"]
    end)
    |> Enum.map(fn file ->
      path = Path.join(folder, file)
      {file, File.stat!(path).ctime}
    end)
    |> Enum.sort_by(fn {_file, ctime} -> ctime end, :desc)
    |> Enum.map(fn {file, _ctime} -> file end)

    {:noreply,
     socket
     |> assign(progress: 0, upload_images: images)}
  end

  def handle_event("toggle-scroll", _params, socket) do
    {:noreply, assign(socket, toggle_scroll: !socket.assigns.toggle_scroll)}
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
    if socket.assigns.slide.transforms do
      active_transforms = Map.get(socket.assigns.slide.transforms, "")
      transforms = if active_transforms do
        Map.put(socket.assigns.slide.transforms, slot, active_transforms)
      else
        Map.delete(socket.assigns.slide.transforms, slot)
      end
      slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
      slides =
        Enum.map(socket.assigns.lesson.slides, fn s ->
          if s.id == slide.id, do: slide, else: s
        end)
      lesson = %{socket.assigns.lesson | slides: slides}
      {:noreply,
       socket
       |> assign(transforms_state: :pending)
       |> assign(slide: slide)
       |> assign(lesson: lesson)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :save)}
  end

  def handle_event("apply-transforms", %{"slot" => slot}, socket) do
    slot_transforms = Map.get(socket.assigns.slide.transforms, slot)
    transforms = Map.put(socket.assigns.slide.transforms, "", slot_transforms)
    slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    slides =
      Enum.map(socket.assigns.lesson.slides, fn s ->
        if s.id == slide.id, do: slide, else: s
      end)
    lesson = %{socket.assigns.lesson | slides: slides}
    {:noreply,
     socket
     |> assign(transforms_state: :pending)
     |> assign(slide: slide)
     |> assign(lesson: lesson)}
  end

  def handle_event("apply-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :apply)}
  end

  def handle_event("clear-transforms", _params, socket) do
    if socket.assigns.slide.transforms do
      transforms = Map.delete(socket.assigns.slide.transforms, "")
      slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
      slides =
        Enum.map(socket.assigns.lesson.slides, fn s ->
          if s.id == slide.id, do: slide, else: s
        end)
      lesson = %{socket.assigns.lesson | slides: slides}
      {:noreply,
       socket
       |> assign(slide: slide)
       |> assign(lesson: lesson)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel-transforms", _params, socket) do
    {:noreply, assign(socket, transforms_state: :pending)}
  end

  def handle_event("flip", %{"item" => item_id}, socket) do
    "image-" <> i = item_id
    image = Enum.at(String.split(socket.assigns.slide.images, "\n"), String.to_integer(i))
    frames = length(String.split(image, " "))
    image_frames = Map.update(socket.assigns.image_frames, item_id, rem(1, frames), &(rem(&1 + 1, frames)))
    {:noreply,
     socket
     |> assign(focus_id: item_id)
     |> assign(image_frames: image_frames)}
  end

  def handle_event("drag", %{"item" => item_id, "x" => x, "y" => y, "z" => z, "size" => size}, socket) do
    active_transforms = Map.get(socket.assigns.slide.transforms, "", socket.assigns.auto_transforms)
    new_active_transforms = Map.put(active_transforms, item_id, [x,y,z,size])
    transforms = Map.put(socket.assigns.slide.transforms || %{}, "", new_active_transforms)
    slide = socket.assigns.slide |> Slide.changeset(%{transforms: transforms}) |> Repo.update!
    slides =
      Enum.map(socket.assigns.lesson.slides, fn s ->
        if s.id == slide.id, do: slide, else: s
      end)
    lesson = %{socket.assigns.lesson | slides: slides}
    {:noreply,
     socket
     |> assign(focus_id: item_id)
     |> assign(slide: slide)
     |> assign(lesson: lesson)}
  end

  def handle_event("hue-left", _params, socket) do
    slide = socket.assigns.slide
    focus_id = socket.assigns.focus_id
    name = get_avatar_name(slide, focus_id)
    if name do
      avatar = Map.get(slide.avatars || %{}, name)
      new_avatar = Map.update(avatar || %{}, "hue", 330, &rem(&1 + 330, 360))
      avatars = Map.put(slide.avatars || %{}, name, new_avatar)
      new_slide = slide |> Slide.changeset(%{avatars: avatars}) |> Repo.update!
      slides =
        Enum.map(socket.assigns.lesson.slides, fn s ->
          if s.id == slide.id, do: slide, else: s
        end)
      lesson = %{socket.assigns.lesson | slides: slides}
      {:noreply,
       socket
       |> assign(slide: new_slide)
       |> assign(lesson: lesson)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("hue-right", _params, socket) do
    slide = socket.assigns.slide
    focus_id = socket.assigns.focus_id
    name = get_avatar_name(slide, focus_id)
    if name do
      avatar = Map.get(slide.avatars || %{}, name)
      new_avatar = Map.update(avatar || %{}, "hue", 30, &rem(&1 + 30, 360))
      avatars = Map.put(slide.avatars || %{}, name, new_avatar)
      new_slide = slide |> Slide.changeset(%{avatars: avatars}) |> Repo.update!
      slides =
        Enum.map(socket.assigns.lesson.slides, fn s ->
          if s.id == slide.id, do: slide, else: s
        end)
      lesson = %{socket.assigns.lesson | slides: slides}
      {:noreply,
       socket
       |> assign(slide: new_slide)
       |> assign(lesson: lesson)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("badge", %{"badge" => badge}, socket) do
    slide = socket.assigns.slide
    focus_id = socket.assigns.focus_id
    name = get_avatar_name(slide, focus_id)
    if name do
      avatar = Map.get(slide.avatars || %{}, name)
      new_avatar = Map.update(avatar || %{}, "badges", [[badge]], &(&1 ++ [[badge]]))
      avatars = Map.put(slide.avatars || %{}, name, new_avatar)
      new_slide = slide |> Slide.changeset(%{avatars: avatars}) |> Repo.update!
      slides =
        Enum.map(socket.assigns.lesson.slides, fn s ->
          if s.id == slide.id, do: slide, else: s
        end)
      lesson = %{socket.assigns.lesson | slides: slides}
      {:noreply,
       socket
       |> assign(slide: new_slide)
       |> assign(lesson: lesson)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete-badge", _params, socket) do
    slide = socket.assigns.slide
    focus_id = socket.assigns.focus_id
    name = get_avatar_name(slide, focus_id)
    if name do
      avatar = Map.get(slide.avatars || %{}, name)
      new_avatar = Map.update(avatar || %{}, "badges", [], fn badges ->
        if badges == [] do
          []
        else
          [_ | rest] = Enum.reverse(badges)
          Enum.reverse(rest)
        end
      end)
      avatars = Map.put(slide.avatars || %{}, name, new_avatar)
      new_slide = slide |> Slide.changeset(%{avatars: avatars}) |> Repo.update!
      slides =
        Enum.map(socket.assigns.lesson.slides, fn s ->
          if s.id == slide.id, do: slide, else: s
        end)
      lesson = %{socket.assigns.lesson | slides: slides}
      {:noreply,
       socket
       |> assign(slide: new_slide)
       |> assign(lesson: lesson)}
    else
      {:noreply, socket}
    end
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
    highlights = if highlight_count >= 2 and highlight_count == length(neighbours) do
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
    [x,y,z,px] = Map.get(active_transforms, item_id, [0,0,1,60])
    "left:#{x}px;top:#{y}px;z-index:#{z};font-size:#{px}px"
  end

  defp get_image_style(active_transforms, item_id, z9999 \\ false) do
    [x,y,z,px] = Map.get(active_transforms, item_id, [0,0,1,200])
    if z9999 do
      "left:#{x}px;top:#{y}px;z-index:9999;width:#{px}px"
    else
      "left:#{x}px;top:#{y}px;z-index:#{z};width:#{px}px"
    end
  end

  defp get_avatar_name_style(active_transforms, item_id) do
    [_,_,_,px] = Map.get(active_transforms, item_id)
    "font-size:#{round(px / 8)}px"
  end

  defp get_avatar_hue(slide, item_id) do
    name = get_avatar_name(slide, item_id)
    if name == nil do
      nil
    else
      avatar = Map.get(slide.avatars || %{}, name)
      Map.get(avatar || %{}, "hue", 6)
    end
  end

  defp get_avatar_badges(slide, item_id) do
    name = get_avatar_name(slide, item_id)
    if name == nil do
      nil
    else
      avatar = Map.get(slide.avatars || %{}, name)
      Map.get(avatar || %{}, "badges", [])
    end
  end

  defp get_avatar_name(slide, item_id) do
    if slide && slide.images && item_id && String.starts_with?(item_id, "image-") do
      "image-" <> i = item_id
      text = Enum.at(String.split(slide.images, "\n"), String.to_integer(i))
      if String.starts_with?(text, "avatar-") do
        "avatar-" <> name = text
        name
      else
        nil
      end
    else
      nil
    end
  end

  defp is_word?(s), do: String.length(s) < 10

  defp auto_transform(slide) do
    words_per_row = 7
    images_per_row = 7

    sentences = String.split(slide.sentences || "", "\n")
    images = String.split(slide.images || "", "\n")
    sentence_rows = Enum.sum_by(Enum.chunk_by(sentences, &is_word?/1), fn [e | rest] ->
      if is_word?(e) do
        Float.ceil(length([e | rest]) / words_per_row)
      else
        length([e | rest]) # one sentence per row
      end
    end)
    image_rows = Float.ceil(length(images) / 10) # ten images per row
    dy = 720 / (sentence_rows + image_rows)
    a = auto_transform_sentences(sentences, dy, words_per_row)
    b = auto_transform_images(images, sentence_rows * dy, dy, images_per_row, length(sentences)+1)
    Map.merge(a, b)
  end

  defp auto_transform_sentences(sentences, dy, words_per_row) do
    dx = 1280 / words_per_row
    separate = Enum.concat(Enum.map(Enum.chunk_by(sentences, &is_word?/1), fn [e | rest] ->
          if is_word?(e) do
            [[e | rest]]
          else
            Enum.map([e | rest], &([&1]))
          end
        end))
    l = Enum.concat(Enum.with_index(separate, fn [e | rest], y ->
          if is_word?(e) do
            Enum.with_index([e | rest], fn _word, x ->
              [100 + round(x * dx), 100 + round(y * dy), 0, 48]
            end)
          else
            [[100, 100 + round(y * dy), 0, 60]]
          end
        end))
    Map.new(Enum.with_index(l, fn [x,y,_,px], i -> {"sentence-#{i}", [x,y,1+i,px]} end))
  end

  defp auto_transform_images(images, begin_y, dy, images_per_row, begin_z) do
    dx = 1280 / images_per_row
    l = Enum.concat(Enum.with_index(Enum.chunk_every(images, images_per_row), fn row, y ->
          Enum.with_index(row, fn _image, x ->
            [100 + round(x * dx), round(begin_y + y * dy), 0, 200]
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

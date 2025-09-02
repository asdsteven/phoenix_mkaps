defmodule MkapsWeb.BoardLive do
  use MkapsWeb, :live_view
  import Ecto.Query, only: [from: 2]
  alias Mkaps.Lesson
  alias Mkaps.Slide
  alias Mkaps.Repo

  def mount(_params, _session, socket) do
    lesson = Repo.one(from lesson in Lesson, order_by: lesson.id, limit: 1) |> Repo.preload(slides: from(s in Slide, order_by: s.position))
    {:ok, assign(socket, page: :play_lesson, play_lesson: lesson, play_index: 0)
    |> allow_upload(:image,
     accept: :any,
     max_file_size: 1_000_000_000,
     progress: fn :image, entry, socket ->
       {:noreply, assign(socket, progress: entry.progress)}
     end
     )}

  end

  def handle_event("list_lesson", _params, socket) do
    {:noreply, assign(socket, page: :list_lesson, list_lesson: Repo.all(from l in Lesson, order_by: l.position))}
  end

  def handle_event("save_lesson", %{"lesson" => lesson_id, "name" => name}, socket) do
    lesson = Repo.get!(Lesson, String.to_integer(lesson_id))
    Lesson.changeset(lesson, %{name: name}) |> Repo.update()
    {:noreply, assign(socket, list_lesson: Repo.all(from l in Lesson, order_by: l.position))}
  end

  def handle_event("create_lesson", %{"name" => name}, socket) do
    max_pos =
      from(l in Lesson, select: max(l.position))
      |> Repo.one()

    next_pos = (max_pos || -1) + 1

    changeset =
      %Lesson{}
      |> Lesson.changeset(%{name: name, position: next_pos})
    Repo.insert!(changeset)
    {:noreply, assign(socket, list_lesson: Repo.all(from l in Lesson, order_by: l.position))}
  end

  def handle_event("move_lesson", %{"lesson" => lesson_id}, socket) do
    Repo.transaction(fn ->
      pos = Repo.get!(Lesson, String.to_integer(lesson_id)).position

      # Find the previous row
      prev =
        from(l in Lesson,
          where: l.position == ^(pos - 1)
        )
        |> Repo.one!()

      # Swap positions
      Repo.update_all(
        from(l in Lesson, where: l.id == ^prev.id),
        set: [position: pos]
      )

      Repo.update_all(
        from(l in Lesson, where: l.id == ^lesson_id),
        set: [position: pos - 1]
      )
    end)
    {:noreply, assign(socket, list_lesson: Repo.all(from l in Lesson, order_by: l.position))}
  end

  def handle_event("edit_lesson", %{"lesson" => lesson_id}, socket) do
    uploads_path = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]
    images = File.ls!(uploads_path)
    |> Enum.filter(fn file ->
      ext = file |> Path.extname() |> String.downcase()
      ext in [".jpg", ".jpeg", ".png", ".gif", ".webp"]
    end)

    lesson = Repo.get!(Lesson, String.to_integer(lesson_id)) |> Repo.preload(slides: from(s in Slide, order_by: s.position))
    {:noreply, assign(socket, page: :edit_lesson, edit_lesson: lesson, progress: 0, images: images)}
  end

  def handle_event("save_slide", %{"slide" => slide_id, "sentences" => sentences, "images" => images}, socket) do
    slide = Repo.get!(Slide, String.to_integer(slide_id))
    Slide.changeset(slide, %{sentences: sentences, images: images}) |> Repo.update()

    lesson = Repo.get!(Lesson, socket.assigns.edit_lesson.id) |> Repo.preload(slides: from(s in Slide, order_by: s.position))
    {:noreply, assign(socket, edit_lesson: lesson)}
  end

  def handle_event("create_slide", %{"sentences" => sentences, "images" => images}, socket) do
    max_pos =
      from(s in Slide, select: max(s.position))
      |> Repo.one()

    next_pos = (max_pos || -1) + 1

    changeset =
      %Slide{}
      |> Slide.changeset(%{sentences: sentences, images: images, position: next_pos, lesson_id: socket.assigns.edit_lesson.id})
    Repo.insert!(changeset)

    lesson = Repo.get!(Lesson, socket.assigns.edit_lesson.id) |> Repo.preload(slides: from(s in Slide, order_by: s.position))
    {:noreply, assign(socket, edit_lesson: lesson)}
  end

  def handle_event("move_slide", %{"slide" => slide_id}, socket) do
    Repo.transaction(fn ->
      pos = Repo.get!(Slide, String.to_integer(slide_id)).position

      # Find the previous row
      prev =
        from(s in Slide,
          where: s.position == ^(pos - 1)
        )
        |> Repo.one!()

      # Swap positions
      Repo.update_all(
        from(s in Slide, where: s.id == ^prev.id),
        set: [position: pos]
      )

      Repo.update_all(
        from(s in Slide, where: s.id == ^slide_id),
        set: [position: pos - 1]
      )
    end)
    lesson = Repo.get!(Lesson, socket.assigns.edit_lesson.id) |> Repo.preload(slides: from(s in Slide, order_by: s.position))
    {:noreply, assign(socket, edit_lesson: lesson)}
  end

  def handle_event("play_lesson", %{"lesson" => lesson_id}, socket) do
    if socket.assigns.play_lesson && lesson_id == socket.assigns.play_lesson.id do
      {:noreply, assign(socket, page: :play_lesson)}
    else
      lesson = Repo.get!(Lesson, String.to_integer(lesson_id)) |> Repo.preload(slides: from(s in Slide, order_by: s.position))
      {:noreply, assign(socket, page: :play_lesson, play_lesson: lesson, play_index: 0)}
    end
  end

  def handle_event("drag_sentence", %{"sentence" => sentence_id, "x" => x, "y" => y, "z" => z}, socket) do
    slide = Repo.get!(Slide, Enum.at(socket.assigns.play_lesson.slides, socket.assigns.play_index).id)
    Slide.changeset(slide, %{sentence_positions: Map.put(slide.sentence_positions || %{}, sentence_id, "left: #{x}px; top: #{y}px; z-index: #{z}")}) |> Repo.update()

    lesson = Repo.get!(Lesson, socket.assigns.play_lesson.id) |> Repo.preload(slides: from(s in Slide, order_by: s.position))
    {:noreply, assign(socket, play_lesson: lesson)}
  end

  def handle_event("reset_positions", _params, socket) do
    slide = Repo.get!(Slide, Enum.at(socket.assigns.play_lesson.slides, socket.assigns.play_index).id)
    Slide.changeset(slide, %{sentence_positions: %{}}) |> Repo.update()

    lesson = Repo.get!(Lesson, socket.assigns.play_lesson.id) |> Repo.preload(slides: from(s in Slide, order_by: s.position))
    {:noreply, assign(socket, play_lesson: lesson)}
  end

  def handle_event("set_slide", %{"slide" => slide_index}, socket) do
    {:noreply, assign(socket, :play_index, String.to_integer(slide_index))}
  end

  def handle_event("prev_slide", _params, socket) do
    {:noreply, update(socket, :play_index, &max(&1 - 1, 0))}
  end

  def handle_event("next_slide", _params, socket) do
    {:noreply, update(socket, :play_index, &min(&1 + 1, length(socket.assigns.play_lesson.slides) - 1))}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", _params, socket) do
    consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
      random_name = Ecto.UUID.generate() <> Path.extname(entry.client_name)
      uploads_path = Application.fetch_env!(:mkaps, MkapsWeb.FileLive)[:uploads_path]
      dest = Path.join(uploads_path, random_name)
      File.cp!(path, dest)
      {:ok, nil}
    end)
    {:noreply, socket}
  end
end

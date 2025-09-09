defmodule Mkaps.Slide do
  use Ecto.Schema
  import Ecto.Changeset

  schema "slides" do
    field :position, :integer
    field :sentences, :string
    field :images, :string
    field :transforms, :map
    field :avatars, :map
    belongs_to :lesson, Mkaps.Lesson
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(slide, attrs) do
    slide
    |> cast(attrs, [:position, :lesson_id, :sentences, :images, :transforms, :avatars])
    |> validate_required([:position, :lesson_id])
  end
end

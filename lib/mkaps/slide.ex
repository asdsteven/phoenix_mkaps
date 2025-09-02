defmodule Mkaps.Slide do
  use Ecto.Schema
  import Ecto.Changeset

  schema "slides" do
    field :position, :integer
    field :sentences, :string
    field :images, :string
    field :sentence_positions, :map
    belongs_to :lesson, Mkaps.Lesson
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(slide, attrs) do
    slide
    |> cast(attrs, [:position, :sentences, :images, :lesson_id, :sentence_positions])
    |> validate_required([:position, :sentences, :images, :lesson_id])
  end
end

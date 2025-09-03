defmodule Mkaps.Slide do
  use Ecto.Schema
  import Ecto.Changeset

  schema "slides" do
    field :position, :integer
    field :sentences, :string
    field :images, :string
    field :font_size, :integer
    field :image_size, :integer
    field :item_xyzs, :map
    field :item_sizes, :map
    belongs_to :lesson, Mkaps.Lesson
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(slide, attrs) do
    slide
    |> cast(attrs, [:position, :sentences, :images, :font_size, :image_size, :item_xyzs, :item_sizes, :lesson_id])
    |> validate_required([:position, :lesson_id])
  end
end

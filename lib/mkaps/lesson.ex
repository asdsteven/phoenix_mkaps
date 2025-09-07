defmodule Mkaps.Lesson do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lessons" do
    field :name, :string
    field :position, :integer
    has_many :slides, Mkaps.Slide, preload_order: [asc: :position]
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lesson, attrs) do
    lesson
    |> cast(attrs, [:name, :position])
    |> validate_required([:name, :position])
  end
end

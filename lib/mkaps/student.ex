defmodule Mkaps.Student do
  use Ecto.Schema
  import Ecto.Changeset

  schema "students" do
    field :name, :string
    field :class_name, :string
    field :class_number, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(student, attrs) do
    student
    |> cast(attrs, [:name, :class_name, :class_number])
    |> validate_required([:name, :class_name, :class_number])
  end
end

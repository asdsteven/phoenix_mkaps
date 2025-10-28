defmodule Mkaps.Pad do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pads" do
    field :name, :string
    field :strokes, :map
    belongs_to :game, Mkaps.Game

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pad, attrs) do
    pad
    |> cast(attrs, [:name, :strokes, :game_id])
    |> validate_required([:name, :game_id])
  end
end

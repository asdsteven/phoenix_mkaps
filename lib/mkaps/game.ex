defmodule Mkaps.Game do
  use Ecto.Schema
  import Ecto.Changeset

  schema "games" do
    field :name, :string
    field :data, :map
    field :layout, :string
    field :position, :integer
    has_many :pads, Mkaps.Pad

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(game, attrs) do
    game
    |> cast(attrs, [:name, :data, :layout, :position])
    |> validate_required([:name, :position])
  end
end

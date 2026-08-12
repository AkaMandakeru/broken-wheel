# frozen_string_literal: true

class AddBattlePassToSeasons < ActiveRecord::Migration[8.1]
  def change
    # Cumulative XP floors, one per level. Empty falls back to Leveling::THRESHOLDS
    # so seasons created before the battle pass keep their 5-level curve.
    add_column :seasons, :level_curve, :jsonb, default: [], null: false
    add_column :seasons, :max_level, :integer, default: 5, null: false

    # The single day boundary for dailies and hour-based challenges.
    add_column :seasons, :time_zone, :string, default: "America/Sao_Paulo", null: false
    add_column :seasons, :slogan, :string
    add_column :seasons, :finalized_at, :datetime
  end
end

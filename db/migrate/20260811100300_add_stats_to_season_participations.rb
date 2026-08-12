# frozen_string_literal: true

# Denormalised season stats, rewritten on every recalculation. These exist so
# the six leaderboards and the season page read one indexed table instead of
# aggregating across `workouts` per request.
class AddStatsToSeasonParticipations < ActiveRecord::Migration[8.1]
  def change
    add_column :season_participations, :premium, :boolean, default: false, null: false
    add_column :season_participations, :premium_granted_at, :datetime

    add_column :season_participations, :total_distance_km, :decimal, precision: 10, scale: 2, default: 0, null: false
    add_column :season_participations, :activities_count, :integer, default: 0, null: false
    add_column :season_participations, :elevation_gain_m, :decimal, precision: 10, scale: 1, default: 0, null: false
    add_column :season_participations, :longest_streak_days, :integer, default: 0, null: false
    add_column :season_participations, :best_5k_seconds, :integer
    add_column :season_participations, :completion_percent, :integer, default: 0, null: false
    add_column :season_participations, :medal_fragments, :integer, default: 0, null: false
    add_column :season_participations, :coins_earned, :integer, default: 0, null: false

    add_index :season_participations, [ :season_id, :total_distance_km ]
    add_index :season_participations, [ :season_id, :activities_count ]
    add_index :season_participations, [ :season_id, :longest_streak_days ]
    add_index :season_participations, [ :season_id, :best_5k_seconds ]
    add_index :season_participations, [ :season_id, :elevation_gain_m ]
    add_index :season_participations, [ :season_id, :xp ]
  end
end

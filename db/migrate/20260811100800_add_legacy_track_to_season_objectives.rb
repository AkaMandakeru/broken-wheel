# frozen_string_literal: true

class AddLegacyTrackToSeasonObjectives < ActiveRecord::Migration[8.1]
  def change
    # standard = the existing club/action objectives; legacy = the five-mission
    # progression that runs parallel to the battle pass.
    add_column :season_objectives, :track, :string, default: "standard", null: false

    # Objectives resolve through ChallengeMetrics like everything else; `kind`
    # stays for the two original club goals and for display grouping.
    add_column :season_objectives, :metric, :string
    add_column :season_objectives, :options, :jsonb, default: {}, null: false
    add_column :season_objectives, :icon, :string
    add_column :season_objectives, :fragment_reward, :integer, default: 0, null: false
    add_column :season_objectives, :coin_reward, :integer, default: 0, null: false

    add_index :season_objectives, [ :season_id, :track ]

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE season_objectives
          SET metric = CASE kind
            WHEN 'join_club'    THEN 'club_member'
            WHEN 'club_workout' THEN 'club_workout_count'
            ELSE 'activity_count'
          END
        SQL
      end
    end
  end
end

# frozen_string_literal: true

class AddTracksToSeasonRewards < ActiveRecord::Migration[8.1]
  def change
    add_column :season_rewards, :track, :string, default: "free", null: false
    add_column :season_rewards, :coins, :integer, default: 0, null: false
    add_column :season_rewards, :position, :integer, default: 0, null: false
    add_column :season_rewards, :payload, :jsonb, default: {}, null: false

    # Rewards are no longer unlocked by level alone — legacy mission sets,
    # completion tiers and community milestones grant through the same path.
    add_column :season_rewards, :unlock_kind, :string, default: "level", null: false
    add_column :season_rewards, :unlock_value, :integer

    # Non-level rewards carry no level.
    change_column_null :season_rewards, :level, true

    add_index :season_rewards, [ :season_id, :unlock_kind, :unlock_value ], name: "index_season_rewards_on_unlock"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE season_rewards SET unlock_kind = 'level', unlock_value = level WHERE level IS NOT NULL
        SQL
      end
    end
  end
end

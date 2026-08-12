# frozen_string_literal: true

# A community goal no longer ends at 100%. Clearing a tier doubles the target
# and opens the next one, so a community that hits its month's goal in week two
# still has something to push toward until the season closes.
class AddTiersToCommunityGoals < ActiveRecord::Migration[8.1]
  def up
    add_column :season_community_goals, :tier, :integer, default: 1, null: false

    # The tier-1 target. Each tier's own target is base × 2^(tier−1).
    add_column :season_community_goals, :base_target_value, :decimal, precision: 14, scale: 2

    # Cumulative value at which the current tier opened, so a tier measures only
    # the distance covered since it began rather than the season total.
    add_column :season_community_goals, :tier_started_value, :decimal, precision: 14, scale: 2, default: 0, null: false

    # Coins paid to every participant when a tier is cleared, scaled by tier.
    add_column :season_community_goals, :tier_coin_reward, :integer, default: 0, null: false

    # nil = keep escalating until the season ends.
    add_column :season_community_goals, :max_tiers, :integer

    add_column :season_community_milestones, :tier, :integer, default: 1, null: false

    # Milestones repeat per tier, so uniqueness is per (goal, tier, percent).
    remove_index :season_community_milestones, name: "idx_community_milestones_unique"
    add_index :season_community_milestones, [ :season_community_goal_id, :tier, :percent ],
              unique: true, name: "idx_community_milestones_unique"

    execute <<~SQL.squish
      UPDATE season_community_goals SET base_target_value = target_value WHERE base_target_value IS NULL
    SQL
  end

  def down
    remove_index :season_community_milestones, name: "idx_community_milestones_unique"
    add_index :season_community_milestones, [ :season_community_goal_id, :percent ],
              unique: true, name: "idx_community_milestones_unique"

    remove_column :season_community_milestones, :tier
    remove_column :season_community_goals, :tier
    remove_column :season_community_goals, :base_target_value
    remove_column :season_community_goals, :tier_started_value
    remove_column :season_community_goals, :tier_coin_reward
    remove_column :season_community_goals, :max_tiers
  end
end

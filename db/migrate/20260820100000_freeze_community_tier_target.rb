# frozen_string_literal: true

# A per-participant goal recomputed its target from the live participant count
# on every read, so someone joining mid-tier pushed the target up and every
# player's progress bar jumped backwards — 38% became 29% because a fourth
# person signed up.
#
# The target is now frozen when a tier opens. New participants raise the bar for
# the *next* tier, never the one in flight.
class FreezeCommunityTierTarget < ActiveRecord::Migration[8.1]
  def up
    add_column :season_community_goals, :tier_target_value, :decimal, precision: 14, scale: 2

    SeasonCommunityGoal.reset_column_information
    SeasonCommunityGoal.find_each do |goal|
      # Freeze whatever the goal is asking for right now, so no in-flight tier
      # shifts under the players currently working on it.
      goal.update_columns(tier_target_value: goal.send(:computed_tier_target))
    end
  end

  def down
    remove_column :season_community_goals, :tier_target_value
  end
end

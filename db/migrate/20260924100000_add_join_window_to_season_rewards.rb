# frozen_string_literal: true

# Participation rewards: something every member of a season gets for taking
# part, rather than for reaching a level or a milestone.
#
# The window is optional and is measured against when a participant JOINED, not
# against the clock at grant time. That is what lets an operator add a banner
# halfway through and say "everyone who was already here, plus anyone who joins
# this week" — and still have it hold when the job runs a day later.
class AddJoinWindowToSeasonRewards < ActiveRecord::Migration[8.1]
  def change
    add_column :season_rewards, :joined_from, :datetime
    add_column :season_rewards, :joined_until, :datetime
    add_index :season_rewards, [ :season_id, :unlock_kind ]
  end
end

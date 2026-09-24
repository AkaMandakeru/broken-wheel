# frozen_string_literal: true

# A participation reward can be delivered two ways. Pushed, which is what the
# "hand out now" button does, or offered: it shows up in the player's locker
# with a Claim button and only becomes theirs when they take it.
#
# Claiming is the better default for a cosmetic. A banner that simply appears is
# easy to miss; one the player chose is one they know they have.
class AddClaimableToSeasonRewards < ActiveRecord::Migration[8.1]
  def change
    add_column :season_rewards, :claimable, :boolean, default: false, null: false
  end
end

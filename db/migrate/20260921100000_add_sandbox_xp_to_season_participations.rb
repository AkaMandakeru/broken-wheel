# frozen_string_literal: true

# XP added by hand from the admin season sandbox, so a tester can put a player
# at any level of a season that has not started yet. Recalculation rebuilds XP
# from ledgers, so an adjustment has to live in one of them to survive it.
#
# Always zero outside the environments the sandbox is enabled in.
class AddSandboxXpToSeasonParticipations < ActiveRecord::Migration[8.1]
  def change
    add_column :season_participations, :sandbox_xp, :integer, default: 0, null: false
  end
end

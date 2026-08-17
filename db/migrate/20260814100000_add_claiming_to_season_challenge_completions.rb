# frozen_string_literal: true

# Challenge XP is now collected by the player rather than appearing on its own.
#
# Completion still happens automatically the moment the workouts qualify — what
# changes is that the XP sits waiting until it is claimed, so finishing a
# challenge is something you see happen instead of a number that moved while you
# were not looking.
class AddClaimingToSeasonChallengeCompletions < ActiveRecord::Migration[8.1]
  def up
    add_column :season_challenge_completions, :claimed_at, :datetime

    # Everything already completed counts as claimed. Without this, existing
    # players would open the app to find their season XP had dropped.
    execute <<~SQL.squish
      UPDATE season_challenge_completions
      SET claimed_at = COALESCE(completed_at, created_at)
      WHERE claimed_at IS NULL
    SQL

    add_index :season_challenge_completions, [ :season_participation_id, :claimed_at ],
              name: "idx_season_completions_claim_state"
  end

  def down
    remove_index :season_challenge_completions, name: "idx_season_completions_claim_state"
    remove_column :season_challenge_completions, :claimed_at
  end
end

# frozen_string_literal: true

# A challenge's own start/end dates belong to whichever season first defined it.
# Reusing that challenge in a later season would measure the *old* season's
# dates — a September season scoring August workouts.
#
# The window now belongs to the season_challenge. Left blank it defaults to the
# season's own window, so a reused challenge automatically measures the new
# season; set explicitly it carves out a narrower slice, which is how the four
# named weeks work.
class AddWindowToSeasonChallenges < ActiveRecord::Migration[8.1]
  def up
    add_column :season_challenges, :starts_at, :datetime
    add_column :season_challenges, :ends_at, :datetime

    # Preserve the windows already in play: copy each challenge's own dates onto
    # its season_challenge, but only where they fall inside that season.
    execute <<~SQL.squish
      UPDATE season_challenges sc
      SET starts_at = c.starts_at, ends_at = c.ends_at
      FROM challenges c, seasons s
      WHERE sc.challenge_id = c.id
        AND sc.season_id = s.id
        AND c.starts_at IS NOT NULL
        AND c.ends_at IS NOT NULL
        AND s.starts_at IS NOT NULL
        AND s.ends_at IS NOT NULL
        AND c.starts_at >= s.starts_at
        AND c.ends_at <= s.ends_at
    SQL
  end

  def down
    remove_column :season_challenges, :starts_at
    remove_column :season_challenges, :ends_at
  end
end

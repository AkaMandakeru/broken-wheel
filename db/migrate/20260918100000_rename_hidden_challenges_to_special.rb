# frozen_string_literal: true

# Secret challenges become Special challenges: players see them from the start
# and work towards them deliberately instead of stumbling into them.
#
# The `hidden` boolean goes with the mechanic. It carried nothing the category
# did not already say — every row with category "hidden" had hidden = true and
# nothing else did — so the category alone is the marker now.
class RenameHiddenChallengesToSpecial < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE season_challenges SET category = 'special' WHERE category = 'hidden'"
    execute "UPDATE season_activities SET kind = 'special_completed' WHERE kind = 'secret_discovered'"
    remove_column :season_challenges, :hidden
  end

  def down
    add_column :season_challenges, :hidden, :boolean, default: false, null: false
    # Restore the flag before the category it is derived from is renamed back.
    execute "UPDATE season_challenges SET hidden = true WHERE category = 'special'"
    execute "UPDATE season_challenges SET category = 'hidden' WHERE category = 'special'"
    execute "UPDATE season_activities SET kind = 'secret_discovered' WHERE kind = 'special_completed'"
  end
end

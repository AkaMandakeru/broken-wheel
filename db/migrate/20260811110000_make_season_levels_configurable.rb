# frozen_string_literal: true

# The level curve is now derived from how many levels a season wants and how
# much XP its top level should cost, rather than being baked in at import.
#
# Without `top_level_xp` the number of levels alone would change difficulty:
# a 10-level season built with the old formula topped out at 3,510 XP, which a
# committed runner passes in the first week. Separating "how many levels" from
# "how much XP to max" lets the level count be a pacing choice.
class MakeSeasonLevelsConfigurable < ActiveRecord::Migration[8.1]
  DEFAULT_TOP_LEVEL_XP = 17_110

  def up
    add_column :seasons, :top_level_xp, :integer
    add_column :seasons, :curve_exponent, :decimal, precision: 4, scale: 2, default: 1.5, null: false

    # Preserve what each existing season already tops out at, so no one's
    # progress shifts under them.
    Season.reset_column_information
    Season.find_each do |season|
      curve = Array(season.level_curve)
      top = curve.last.presence || DEFAULT_TOP_LEVEL_XP
      season.update_columns(top_level_xp: top.to_i, max_level: [ curve.size, season.max_level, 1 ].compact.max)
    end
  end

  def down
    remove_column :seasons, :top_level_xp
    remove_column :seasons, :curve_exponent
  end
end

# frozen_string_literal: true

# Season XP → level curve. Five levels; thresholds are cumulative XP floors.
module Leveling
  # index 0 = level 1 floor, ... index 4 = level 5 floor
  THRESHOLDS = [ 0, 100, 300, 600, 1000 ].freeze
  MAX_LEVEL = THRESHOLDS.size

  module_function

  def level_for(xp)
    xp = xp.to_i
    level = 1
    THRESHOLDS.each_with_index { |floor, i| level = i + 1 if xp >= floor }
    level
  end

  def max_level?(xp)
    level_for(xp) >= MAX_LEVEL
  end

  # XP floor where the given level starts.
  def floor_for(level)
    THRESHOLDS[level - 1] || THRESHOLDS.last
  end

  # XP floor of the next level, or nil when already maxed.
  def next_floor(xp)
    THRESHOLDS.find { |floor| floor > xp.to_i }
  end

  # Percent progress toward the next level (100 when maxed).
  def progress_percent(xp)
    xp = xp.to_i
    level = level_for(xp)
    return 100 if level >= MAX_LEVEL

    floor = THRESHOLDS[level - 1]
    ceil = THRESHOLDS[level]
    ((xp - floor).to_f / (ceil - floor) * 100).round
  end
end

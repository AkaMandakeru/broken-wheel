# frozen_string_literal: true

module Seasons
  # Per-season XP → level mapping. Replaces the global 5-level `Leveling`
  # constant so each season can run as many or as few levels as it wants.
  #
  # A curve is described by two independent numbers:
  #
  #   max_level    — how many levels the pass has (pacing)
  #   top_level_xp — what the last level costs   (difficulty)
  #
  # Keeping them separate is the point: dropping a season from 30 levels to 10
  # should change how often players level up, not how hard the season is. The
  # thresholds are spread across the same XP range either way.
  class LevelCurve
    DEFAULT_TOP_LEVEL_XP = 17_110
    DEFAULT_EXPONENT = 1.5

    # Legacy shape, kept so seasons imported before configurable curves can
    # still be rebuilt exactly as they were.
    SLOPE = 300
    CURVE = 10

    attr_reader :thresholds

    def self.for(season)
      new(season&.level_curve.presence || Leveling::THRESHOLDS)
    end

    # Spreads `max_level` thresholds from 0 to `top_xp`.
    #
    # An exponent above 1 front-loads the curve — early levels arrive quickly
    # and the last third is earned — which is what keeps a battle pass moving
    # for a newcomer without making the top level cheap.
    def self.build(max_level, top_xp: DEFAULT_TOP_LEVEL_XP, exponent: DEFAULT_EXPONENT)
      levels = max_level.to_i
      return [ 0 ] if levels <= 1

      top = top_xp.to_i
      power = exponent.to_f.positive? ? exponent.to_f : DEFAULT_EXPONENT

      (1..levels).map do |n|
        ratio = (n - 1).to_f / (levels - 1)
        (top * (ratio**power)).round
      end
    end

    # The pre-configurable quadratic, for rebuilding legacy curves.
    def self.build_legacy(max_level, slope: SLOPE, curve: CURVE)
      (1..max_level.to_i).map { |n| (slope * (n - 1)) + (curve * (n - 1)**2) }
    end

    def initialize(thresholds)
      @thresholds = Array(thresholds).map(&:to_i).sort
      @thresholds = Leveling::THRESHOLDS.dup if @thresholds.empty?
    end

    def max_level
      thresholds.size
    end

    def top_xp
      thresholds.last.to_i
    end

    def level_for(xp)
      xp = xp.to_i
      level = 1
      thresholds.each_with_index { |floor, i| level = i + 1 if xp >= floor }
      level
    end

    def max_level?(xp)
      level_for(xp) >= max_level
    end

    def floor_for(level)
      thresholds[level - 1] || thresholds.last
    end

    def next_floor(xp)
      thresholds.find { |floor| floor > xp.to_i }
    end

    # Percent progress toward the next level (100 when maxed).
    def progress_percent(xp)
      xp = xp.to_i
      level = level_for(xp)
      return 100 if level >= max_level

      floor = thresholds[level - 1]
      ceil  = thresholds[level]
      return 100 if ceil == floor

      (((xp - floor).to_f / (ceil - floor)) * 100).round
    end

    def xp_to_next(xp)
      floor = next_floor(xp)
      floor ? floor - xp.to_i : 0
    end
  end
end

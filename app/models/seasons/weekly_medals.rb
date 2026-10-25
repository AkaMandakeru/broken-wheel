# frozen_string_literal: true

module Seasons
  # A weekly challenge's requirements run easiest to hardest, so the first
  # earns bronze, the second silver, the third gold. Anything beyond the third
  # has no medal — the ladder only makes sense while the tiers are distinct.
  #
  # Lives here rather than in SeasonsHelper so the season page and the mobile
  # API award the same medal from the same rule.
  module WeeklyMedals
    TIERS = %w[bronze silver gold].freeze

    module_function

    def for_requirement(position)
      TIERS[position]
    end

    # The best medal earned on a challenge: the highest tier whose requirement
    # is met. Nil when none are.
    def highest_earned(challenge_participation, statuses: nil)
      return nil if challenge_participation.nil?

      statuses ||= challenge_participation.requirement_status
      return nil if statuses.empty?

      earned = statuses.first(TIERS.size).each_with_index.select { |status, _i| status[:met] }
      return nil if earned.empty?

      TIERS[earned.map(&:last).max]
    end
  end
end

# frozen_string_literal: true

# The signed-in player's standing in a season.
class SeasonParticipationResource < ApplicationResource
  attributes :xp, :level, :premium, :rank, :progress_percent, :xp_to_next_level,
             :unclaimed_count, :unclaimed_xp, :coins_earned, :activities_count,
             :longest_streak_days, :completion_percent, :best_5k_seconds

  attribute(:max_level_reached) { |participation| participation.max_level? }
  attribute(:total_distance_km) { |participation| participation.total_distance_km.to_f }
  attribute(:elevation_gain_m) { |participation| participation.elevation_gain_m.to_f }

  # The player's wallet, which season rewards and dailies pay into.
  attribute(:coins) { |participation| participation.user.coins.to_i }

  attribute :medal do |participation|
    {
      tier: participation.medal_tier,
      fragments: participation.medal_fragments,
      next_tier: participation.next_medal_tier,
      fragments_to_next: participation.fragments_to_next_medal,
      progress_percent: participation.medal_progress_percent
    }
  end
end

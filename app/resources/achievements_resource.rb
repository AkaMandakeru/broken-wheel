# frozen_string_literal: true

# The medal shelf: an Achievements::Shelf.
class AchievementsResource < ApplicationResource
  attribute(:seasons_played) { |shelf| shelf.participations.size }
  attribute(:medals_earned) { |shelf| shelf.medals.size }
  attribute(:fragments, &:fragments)

  # Every tier, in ladder order, so the app can draw the empty slots too.
  attribute :medal_counts do |shelf|
    SeasonParticipation::MEDAL_TIERS.keys.index_with { |tier| shelf.medal_counts[tier].to_i }
  end

  attribute :seasons do |shelf|
    shelf.participations.map do |participation|
      SeasonMedalResource.new(participation, params: { browsable: shelf.browsable_season_ids.include?(participation.season_id) })
                         .serializable_hash
    end
  end

  attribute :reward_badges do |shelf|
    shelf.reward_badges.map do |user_badge|
      { id: user_badge.badge.id, name: user_badge.badge.display_name, icon: user_badge.badge.icon,
        earned_at: user_badge.earned_at&.iso8601 }
    end
  end
end

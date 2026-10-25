# frozen_string_literal: true

# The viewer's progress in a challenge, for one season context.
class ChallengeParticipationResource < ApplicationResource
  attributes :id, :season_id, :percent_complete

  attribute(:progress_value) { |participation| participation.progress_value.to_f }
  attribute(:completed, &:completed?)
  attribute(:completed_at) { |participation| participation.completed_at&.iso8601 }
  attribute(:joined_at) { |participation| participation.created_at.iso8601 }

  attribute :requirements do |participation|
    participation.requirement_status.map do |status|
      { requirement_id: status[:requirement].id, value: status[:value]&.to_f, percent: status[:percent], met: status[:met] }
    end
  end
end

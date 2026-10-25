# frozen_string_literal: true

# A challenge in the list. `params[:participations]` is
# Challenges::Context.participation_index for the viewer.
class ChallengeResource < ApplicationResource
  attributes :id, :key, :challenge_type, :sport, :status, :target_unit

  attribute(:title, &:display_title)
  attribute(:description, &:display_description)
  attribute(:target_value) { |challenge| challenge.target_value&.to_f }
  attribute(:starts_at) { |challenge| challenge.starts_at&.iso8601 }
  attribute(:ends_at) { |challenge| challenge.ends_at&.iso8601 }
  attribute(:image) { |challenge| ImageUrls.urls(challenge.image, :card, :hero) }

  attribute :requirements do |challenge|
    ChallengeRequirementResource.new(challenge.challenge_requirements).serializable_hash
  end

  attribute :my_participation do |challenge|
    participation = params[:participations]&.[](challenge.id)
    participation && ChallengeParticipationResource.new(participation).serializable_hash
  end
end

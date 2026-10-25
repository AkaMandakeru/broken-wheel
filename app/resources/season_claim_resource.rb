# frozen_string_literal: true

# A finished challenge whose XP is waiting to be collected.
class SeasonClaimResource < ApplicationResource
  attributes :id, :season_challenge_id

  attribute(:xp) { |completion| completion.xp_awarded }
  attribute(:title) { |completion| completion.season_challenge.challenge.display_title }
  attribute(:category) { |completion| completion.season_challenge.category }
  attribute(:completed_at) { |completion| completion.completed_at.iso8601 }
end

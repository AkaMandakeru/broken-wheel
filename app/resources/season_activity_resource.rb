# frozen_string_literal: true

# A line of the season feed. `user` is nil for community-wide entries.
class SeasonActivityResource < ApplicationResource
  attributes :id, :kind

  attribute(:text) { |activity| activity.description }
  attribute(:community) { |activity| activity.community? }
  attribute(:created_at) { |activity| activity.created_at.iso8601 }
  attribute(:user) { |activity| activity.user && UserSummaryResource.new(activity.user).serializable_hash }
end

# frozen_string_literal: true

class TimelineCommentResource < ApplicationResource
  attributes :id, :timeline_post_id, :content

  attribute(:created_at) { |comment| comment.created_at.iso8601 }
  attribute(:user) { |comment| UserSummaryResource.new(comment.user).serializable_hash }
  attribute(:mine) { |comment| comment.user_id == viewer&.id }
end

# frozen_string_literal: true

# A post on a challenge's timeline. `params[:blocked_ids]` hides comments from
# players the viewer has blocked (the posts themselves are filtered by the query).
class TimelinePostResource < ApplicationResource
  attributes :id, :challenge_id, :content

  attribute(:created_at) { |post| post.created_at.iso8601 }
  attribute(:user) { |post| UserSummaryResource.new(post.user).serializable_hash }
  attribute(:mine) { |post| post.user_id == viewer&.id }
  attribute(:workout) { |post| post.workout && AttachedWorkoutResource.new(post.workout).serializable_hash }
  attribute(:images) { |post| post.images.map { |image| ImageUrls.urls(image, :thumb, :large) } }

  attribute :comments do |post|
    blocked = params[:blocked_ids] || []
    comments = post.timeline_post_comments.reject { |comment| blocked.include?(comment.user_id) }.sort_by { |c| [ c.created_at, c.id ] }
    TimelineCommentResource.new(comments, params: params).serializable_hash
  end
end

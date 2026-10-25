# frozen_string_literal: true

class UserBlockResource < ApplicationResource
  attribute(:blocked_at) { |block| block.created_at.iso8601 }
  attribute(:user) { |block| UserSummaryResource.new(block.blocked).serializable_hash }
end

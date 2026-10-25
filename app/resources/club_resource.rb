# frozen_string_literal: true

# A club in the list. `params[:membership_ids]` is the set of club ids the
# viewer belongs to.
class ClubResource < ApplicationResource
  attributes :id, :name, :description, :sport, :member_count

  attribute(:created_at) { |club| club.created_at.iso8601 }
  attribute(:created_by) { |club| UserSummaryResource.new(club.created_by).serializable_hash }
  attribute(:member) { |club| params[:membership_ids]&.include?(club.id) || false }
end

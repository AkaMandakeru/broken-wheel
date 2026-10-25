# frozen_string_literal: true

# One club's page: `params[:membership]` is the viewer's ClubMembership (or nil).
class ClubDetailResource < ClubResource
  attribute(:member) { |_club| params[:membership].present? }

  attribute :my_membership do |_club|
    membership = params[:membership]
    membership && { role: membership.role, joined_at: membership.created_at.iso8601 }
  end

  attribute :members do |club|
    memberships = club.club_memberships.includes(user: { avatar_attachment: :blob }).order(:created_at, :id)
    memberships.map do |membership|
      { role: membership.role, joined_at: membership.created_at.iso8601, user: UserSummaryResource.new(membership.user).serializable_hash }
    end
  end
end

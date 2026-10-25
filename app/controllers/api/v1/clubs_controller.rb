# frozen_string_literal: true

module Api
  module V1
    # Clubs. Joining, leaving and founding go through Clubs::Membership, the
    # same object the web uses, so member counts, analytics and the season
    # objectives a membership unlocks stay identical on both.
    class ClubsController < BaseController
      requires_feature :clubs
      idempotent only: [ :create, :join ]

      before_action :set_club, only: [ :show, :join, :leave ]

      def index
        clubs, meta = paginate(Club.for_sports(current_user.sports).reorder(member_count: :desc, id: :desc)
                                   .includes(created_by: { avatar_attachment: :blob }))
        membership_ids = current_user.club_memberships.where(club_id: clubs.map(&:id)).pluck(:club_id).to_set

        render_collection ClubResource, clubs, meta: meta, membership_ids: membership_ids
      end

      def show
        render_detail
      end

      def create
        club = Club.new(params.expect(club: [ :name, :description, :sport ]))
        return render_invalid(club) unless ::Clubs::Membership.create_with_founder(club, current_user)

        track_event "api.club.created", club_id: club.id
        @club = club
        render_detail status: :created
      end

      def join
        return render_error(:conflict, "already_member") unless membership.join

        track_event "api.club.joined", club_id: @club.id
        render_detail status: :created
      end

      def leave
        return render_error(:not_found, "not_member") unless membership.leave

        track_event "api.club.left", club_id: @club.id
        head :no_content
      end

      private

      def set_club
        @club = Club.find(params[:id])
      end

      def membership
        @membership ||= ::Clubs::Membership.new(@club, current_user)
      end

      def render_detail(status: :ok)
        render_resource ClubDetailResource, @club.reload, status: status, membership: membership.current
      end
    end
  end
end

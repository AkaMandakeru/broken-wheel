# frozen_string_literal: true

module Api
  module V1
    # The season list and the season page's header. Public like the web: a
    # guest sees the season, a player also sees their own standing.
    class SeasonsController < Seasons::BaseController
      allow_unauthenticated_access only: [ :index, :show ]
      skip_before_action :set_season, only: :index

      # The running season(s) and the one finished season still open to look
      # back on — the same two lists as the web's season index.
      def index
        active = Season.active.by_recent.with_attached_image.to_a
        archive = Season.recent_archive.with_attached_image.to_a
        return unless stale?(etag: [ active, archive, I18n.locale, Date.current ])

        render_data({
          active: SeasonResource.new(active).serializable_hash,
          archive: SeasonResource.new(archive).serializable_hash
        })
      end

      # Viewing an active season enrolls the player, exactly like the web page.
      def show
        dashboard.enroll!
        return unless stale_section?(
          @season.season_challenges.maximum(:updated_at), dashboard.challenge_progress_updated_at,
          dashboard.participation&.unclaimed_count, announcement_state, @season.current_date
        )

        render_resource SeasonOverviewResource, dashboard
      end

      private

      # Dismissing the banner doesn't touch the user's updated_at, so it is
      # keyed separately.
      def announcement_state
        current_user && [ current_user.dismissed_season_announcement?(@season.id), ::Seasons::Announcement.for(current_user)&.id ]
      end
    end
  end
end

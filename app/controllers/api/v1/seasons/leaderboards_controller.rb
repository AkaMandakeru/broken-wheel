# frozen_string_literal: true

module Api
  module V1
    module Seasons
      # One leaderboard (?board=xp|distance|activities|streak|fastest_5k|elevation,
      # xp by default): the top ten and the viewer's own position.
      class LeaderboardsController < BaseController
        allow_unauthenticated_access only: :show

        def show
          return unless stale_section?(dashboard.board, @season.season_participations.maximum(:updated_at))

          render_resource SeasonLeaderboardResource, dashboard
        end
      end
    end
  end
end

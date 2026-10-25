# frozen_string_literal: true

module Api
  module V1
    module Seasons
      # Shared by the season endpoints: the feature switch, the season lookup
      # (players reach only browsable seasons, admins every one — anything else
      # is a 404) and the Seasons::Dashboard each section is read from.
      class BaseController < Api::V1::BaseController
        requires_feature :seasons
        before_action :set_season

        private

        def set_season
          @season = season_scope.find(params[:season_id] || params[:id])
        end

        def season_scope
          ::Seasons::Dashboard.season_scope(current_user)
        end

        def dashboard
          @dashboard ||= ::Seasons::Dashboard.new(@season, user: current_user, board: params[:board])
        end

        # Conditional GET for a section. The key always carries the season, who
        # is asking, their participation (its updated_at moves on every
        # recalculation and claim) and the language; `parts` adds what else the
        # section depends on.
        def stale_section?(*parts)
          stale?(etag: [ @season, current_user, dashboard.participation, I18n.locale, *parts ])
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Seasons
      # The community goal, or null when the season has none.
      class CommunityController < BaseController
        allow_unauthenticated_access only: :show

        def show
          goal = dashboard.community_goal
          return unless stale?(etag: [ goal, goal&.season_community_milestones&.map(&:cache_key_with_version), I18n.locale ])

          render_data(goal && SeasonCommunityGoalResource.new(goal).serializable_hash)
        end
      end
    end
  end
end

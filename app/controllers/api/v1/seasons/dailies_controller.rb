# frozen_string_literal: true

module Api
  module V1
    module Seasons
      # Today's three dailies. A player with no set yet (they joined today) gets
      # one drawn on the spot — the same deterministic draw the nightly job
      # makes. Not cached: the values are live from the player's workouts.
      class DailiesController < BaseController
        def index
          dashboard.enroll!
          assignments = dashboard.daily_assignments

          render_data({
            date: @season.current_date.iso8601,
            completed_count: assignments.count(&:completed?),
            total: assignments.size,
            dailies: SeasonDailyResource.new(assignments, params: { progress: dashboard.daily_progress }).serializable_hash
          })
        end
      end
    end
  end
end

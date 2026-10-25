# frozen_string_literal: true

module Api
  module V1
    module Seasons
      # Club and action objectives, and the legacy missions track.
      class ObjectivesController < BaseController
        allow_unauthenticated_access only: :index

        def index
          completed_ids = dashboard.completed_objective_ids
          return unless stale_section?(@season.season_objectives.maximum(:updated_at), completed_ids)

          render_data({
            objectives: serialize(dashboard.objectives, completed_ids),
            legacy_missions: {
              completed_count: dashboard.legacy_completed_count,
              total: dashboard.legacy_missions.size,
              missions: serialize(dashboard.legacy_missions, completed_ids)
            }
          })
        end

        private

        def serialize(objectives, completed_ids)
          SeasonObjectiveResource.new(objectives, params: { completed_ids: completed_ids }).serializable_hash
        end
      end
    end
  end
end

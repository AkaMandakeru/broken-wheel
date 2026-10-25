# frozen_string_literal: true

module Api
  module V1
    module Seasons
      # The season's activity feed, newest first.
      class ActivitiesController < BaseController
        allow_unauthenticated_access only: :index

        def index
          activities, meta = paginate(dashboard.activities_scope)
          return unless stale?(etag: [ @season, activities, current_user, I18n.locale, meta ])

          render_collection SeasonActivityResource, activities, meta: meta
        end
      end
    end
  end
end

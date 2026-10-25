# frozen_string_literal: true

module Api
  module V1
    # The medal shelf, as on the web's achievements page.
    class AchievementsController < BaseController
      requires_feature :achievements

      def index
        render_resource AchievementsResource, Achievements::Shelf.new(current_user)
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Seasons
      # Closes the "a new season has started" banner for good.
      class AnnouncementsController < BaseController
        def dismiss
          ::Seasons::Announcement.dismiss!(current_user, @season.id)

          head :no_content
        end
      end
    end
  end
end

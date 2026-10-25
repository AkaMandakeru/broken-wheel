# frozen_string_literal: true

module Api
  module V1
    module Seasons
      # The season board: every challenge, in the sections the season page
      # shows, with the viewer's progress per challenge and per requirement.
      class ChallengesController < BaseController
        # The web page's sections, in its order. Weeklies run by week number.
        SECTIONS = %w[weekly monthly elite standard special].freeze

        allow_unauthenticated_access only: :index

        def index
          return unless stale_section?(
            @season.season_challenges.maximum(:updated_at), dashboard.challenge_progress_updated_at, @season.current_date
          )

          render_data({ sections: SECTIONS.filter_map { |category| section(category) } })
        end

        private

        def section(category)
          items = category == "weekly" ? dashboard.weekly_challenges : dashboard.challenges_by_category[category]
          return nil if items.blank?

          {
            category: category,
            label: I18n.t("seasons.categories.#{category}", default: category.humanize),
            challenges: SeasonChallengeResource.new(
              items, params: { progress: dashboard.challenge_progress, participation: dashboard.participation }
            ).serializable_hash
          }
        end
      end
    end
  end
end

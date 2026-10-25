# frozen_string_literal: true

module Api
  module V1
    module Seasons
      # XP waiting on finished challenges, and collecting it — one completion
      # (POST …/claims/:id) or all of them (POST …/claims).
      #
      # A claim is a conditional stamp on the completion row (see
      # SeasonChallengeCompletion#claim!), so a double tap or a retry never pays
      # twice; the Idempotency-Key on top lets a retry get the first answer back.
      class ClaimsController < BaseController
        before_action :set_participation
        idempotent only: :create

        def index
          completions = @participation.unclaimed_completions.to_a

          render_collection SeasonClaimResource, completions,
                            meta: { count: completions.size, xp: completions.sum(&:xp_awarded) }
        end

        def create
          if params[:id].present?
            completion = @participation.season_challenge_completions.find_by(id: params[:id])
            # Rendered rather than raised, so the idempotency key is closed out
            # with this answer instead of being left in progress.
            return render_error(:not_found, "not_found") unless completion
          end

          result = SeasonXpClaimer.new(@participation).call(completion: completion)

          track_event "api.season.claimed", season_id: @season.id, claimed: result.claimed, xp: result.xp
          render_data(result.summary)
        end

        private

        # Same reach as the web's claim endpoint: browsable seasons only, admin
        # or not. Collecting XP on a closed season would change a final result.
        def season_scope
          Season.browsable
        end

        def set_participation
          @participation = current_user.season_participations.find_by(season_id: @season.id)
          return if @participation

          render_error :not_found, "season_not_joined"
        end
      end
    end
  end
end

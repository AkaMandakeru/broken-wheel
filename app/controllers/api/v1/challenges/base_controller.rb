# frozen_string_literal: true

module Api
  module V1
    module Challenges
      # The timeline belongs to a challenge's participants (any season), the
      # same rule as the web's TimelinePostsController#ensure_participant.
      class BaseController < Api::V1::BaseController
        requires_feature :challenges

        before_action :set_challenge
        before_action :ensure_participant

        private

        def set_challenge
          @challenge = Challenge.find(params[:challenge_id])
        end

        def ensure_participant
          return if ::Challenges::Context.participant?(current_user, @challenge)

          render_error :forbidden, "not_participant"
        end

        def blocked_ids
          @blocked_ids ||= UserBlock.where(blocker: current_user).pluck(:blocked_id)
        end
      end
    end
  end
end

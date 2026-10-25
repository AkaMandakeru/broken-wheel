# frozen_string_literal: true

module Api
  module V1
    # Challenges outside the season screens. Which season a challenge is read
    # in comes from ::Challenges::Context, the same object the web page uses.
    class ChallengesController < BaseController
      requires_feature :challenges
      idempotent only: :join

      before_action :set_challenge, except: :index

      def index
        type = params[:type].presence_in(Challenge::CHALLENGE_TYPES)
        challenges = ::Challenges::Context.listing(type: type).includes(:challenge_requirements, image_attachment: :blob).to_a
        participations = ::Challenges::Context.participation_index(current_user, challenges)

        render_collection ChallengeResource, challenges, participations: participations
      end

      def show
        render_resource ChallengeDetailResource, @challenge, context: context
      end

      def join
        return render_error(:conflict, "already_joined") unless context.join!

        track_event "api.challenge.joined", challenge_id: @challenge.id, season_id: context.season&.id
        render_resource ChallengeDetailResource, @challenge, status: :created, context: context
      end

      # A link to share. Opening it shows the challenge (a universal link in the
      # app); the invite code identifies who invited.
      def invite
        participation = context.participation
        return render_error(:forbidden, "must_join_first") unless participation

        render_data({ invite_code: participation.invite_code, url: challenge_url(@challenge),
                      title: @challenge.display_title, message: I18n.t("api.challenges.invite_message", title: @challenge.display_title) })
      end

      private

      def set_challenge
        @challenge = Challenge.find(params[:id])
      end

      def context
        @context ||= ::Challenges::Context.new(@challenge, user: current_user)
      end
    end
  end
end

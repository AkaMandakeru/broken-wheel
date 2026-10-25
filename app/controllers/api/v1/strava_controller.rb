# frozen_string_literal: true

module Api
  module V1
    # Strava on mobile. The app opens `authorize_url` in an auth session, Strava
    # redirects to the app's universal link, and the app posts the code here:
    # the code is exchanged on the server, so the client secret never ships.
    class StravaController < BaseController
      requires_feature :integrations
      idempotent only: :import

      PREVIEW_SIZE = 50
      MAX_IMPORT = 50

      before_action :require_connection, only: [ :activities, :import ]

      rescue_from StravaService::Error do |error|
        Rails.logger.error("Strava error for user=#{current_user&.id}: #{error.message}")
        render_error :bad_gateway, "strava_unavailable"
      end

      rescue_from StravaService::RateLimitError do
        render_error :too_many_requests, "strava_rate_limited"
      end

      # Not 401: that would tell the app its own session ended and sign the
      # player out. Only the Strava link needs redoing.
      rescue_from StravaService::AuthError do
        render_error :conflict, "strava_auth_failed"
      end

      def authorize
        state = Strava::Connection.state_for(current_user)
        url = Strava::Connection.authorize_url(redirect_uri: redirect_uri, mobile: true, state: state)
        render_data({ authorize_url: url, state: state })
      end

      def callback
        callback = params.permit(:code, :state, :scope, :error)
        unless Strava::Connection.valid_state?(current_user, callback[:state])
          return render_error(:unprocessable_content, "invalid_state")
        end
        return render_error(:unprocessable_content, "strava_connect_failed") if callback[:error].present? || callback[:code].blank?

        Strava::Connection.new(current_user).connect!(code: callback[:code], scope: callback[:scope])
        SyncStravaActivitiesJob.perform_later(current_user.id)
        track_event "api.strava.connected"

        render_resource IntegrationResource, Integration.strava(current_user)
      rescue Strava::Errors::Fault => error
        Rails.logger.error("Strava OAuth token exchange failed: #{error.message}")
        render_error :unprocessable_content, "strava_connect_failed"
      end

      def activities
        activities = StravaService.new(current_user).activities(page_size: PREVIEW_SIZE).to_a
        imported_ids = current_user.workouts.where(provider: Strava::ActivityImporter::PROVIDER).pluck(:external_id).to_set
        render_collection StravaActivityResource, activities, imported_ids: imported_ids
      end

      def import
        activity_ids = Array(params.permit(activity_ids: [])[:activity_ids]).map(&:to_s).compact_blank.uniq
        return render_error(:unprocessable_content, "no_activities_selected") if activity_ids.empty?
        if activity_ids.size > MAX_IMPORT
          return render_error(:unprocessable_content, "too_many_activities",
                              message: I18n.t("api.errors.too_many_activities", count: MAX_IMPORT))
        end

        ImportStravaActivitiesJob.perform_later(current_user.id, activity_ids)
        track_event "api.strava.import_requested", requested_count: activity_ids.size
        render_data({ requested_count: activity_ids.size }, status: :accepted)
      end

      def destroy
        Strava::Connection.new(current_user).disconnect!
        track_event "api.strava.disconnected"
        head :no_content
      end

      private

      def require_connection
        render_error :unprocessable_content, "strava_not_connected" unless current_user.connected_to_strava?
      end

      # Strava sends the player back to the app's universal link. Without one
      # configured (development), the web callback still completes the flow.
      def redirect_uri
        ENV["STRAVA_MOBILE_REDIRECT_URI"].presence || auth_strava_callback_url
      end
    end
  end
end

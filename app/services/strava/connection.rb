# frozen_string_literal: true

module Strava
  # Linking and unlinking a player's Strava account, for the web OAuth flow and
  # the app's (which opens Strava's mobile authorize page and posts the code
  # back). The client secret stays on the server: the code is always exchanged
  # here.
  class Connection
    SCOPE = "read,activity:read_all"
    MOBILE_OAUTH_ENDPOINT = "https://www.strava.com/oauth/mobile"
    STATE_PURPOSE = :strava_connect
    STATE_TTL = 10.minutes

    class << self
      # `mobile: true` points at the page that hands over to the Strava app
      # when it is installed.
      def authorize_url(redirect_uri:, mobile: false, state: nil)
        client = mobile ? build_client(endpoint: MOBILE_OAUTH_ENDPOINT) : build_client
        client.authorize_url(
          { redirect_uri: redirect_uri, scope: SCOPE, approval_prompt: "auto",
            response_type: "code", state: state }.compact
        )
      end

      # A short-lived token bound to the player, so a code posted back can only
      # link the account of whoever started the flow.
      def state_for(user)
        state_verifier.generate({ "user_id" => user.id, "nonce" => SecureRandom.hex(8) },
                                purpose: STATE_PURPOSE, expires_in: STATE_TTL)
      end

      def valid_state?(user, state)
        payload = state_verifier.verified(state.to_s, purpose: STATE_PURPOSE)
        payload.is_a?(Hash) && payload["user_id"] == user.id
      rescue ArgumentError
        false
      end

      private

      def build_client(**options)
        Strava::OAuth::Client.new(client_id: ENV.fetch("STRAVA_CLIENT_ID"),
                                  client_secret: ENV.fetch("STRAVA_CLIENT_SECRET"), **options)
      end

      def state_verifier
        Rails.application.message_verifier(:strava_state)
      end
    end

    def initialize(user)
      @user = user
    end

    # Exchanges the authorization code and stores (or replaces) the token.
    # Raises Strava::Errors::Fault when Strava refuses the code.
    def connect!(code:, scope:)
      response = StravaService.build_oauth_client.oauth_token(code: code)
      athlete_id = response.athlete&.id

      token = @user.strava_token || @user.build_strava_token
      token.update!(
        access_token:  response.access_token,
        refresh_token: response.refresh_token,
        expires_at:    response.expires_at.to_i,
        athlete_id:    athlete_id,
        scope:         scope.to_s
      )

      Analytics.track(user: @user, event: "user_connected_strava",
                      properties: { athlete_id: athlete_id, scope: scope.to_s })
      token
    end

    def disconnect!
      @user.strava_token&.destroy
    end
  end
end

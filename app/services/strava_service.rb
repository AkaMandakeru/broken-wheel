# frozen_string_literal: true

class StravaService
  class Error < StandardError; end
  class AuthError < Error; end
  class RateLimitError < Error; end

  def initialize(user)
    @user  = user
    @token = user.strava_token
    raise AuthError, "User is not connected to Strava" if @token.nil?

    refresh_token! if @token.expired?
  end

  def athlete
    api_client.athlete
  rescue Strava::Errors::Fault => e
    handle_fault!(e)
  end

  def activities(page_size: 30, after: nil, &block)
    opts = { page_size: page_size }
    opts[:after] = after.to_i if after

    api_client.athlete_activities(opts, &block)
  rescue Strava::Errors::Fault => e
    handle_fault!(e)
  end

  def activity(id)
    api_client.activity(id)
  rescue Strava::Errors::Fault => e
    handle_fault!(e)
  end

  private

  def api_client
    @api_client ||= Strava::Api::Client.new(access_token: @token.access_token)
  end

  def oauth_client
    @oauth_client ||= self.class.build_oauth_client
  end

  def self.build_oauth_client
    Strava::OAuth::Client.new(
      client_id: ENV.fetch("STRAVA_CLIENT_ID"),
      client_secret: ENV.fetch("STRAVA_CLIENT_SECRET")
    )
  end

  def handle_fault!(error)
    status = error.response&.dig(:status)
    message = error.message.to_s rescue error.class.name

    case status
    when 401, 403
      raise AuthError, "Strava authorization rejected (HTTP #{status})"
    when 429
      raise RateLimitError, "Strava rate limit hit"
    else
      raise Error, "Strava API error (HTTP #{status}): #{message}"
    end
  end

  def refresh_token!
    response = oauth_client.oauth_token(
      grant_type: "refresh_token",
      refresh_token: @token.refresh_token
    )

    @token.update!(
      access_token:  response.access_token,
      refresh_token: response.refresh_token || @token.refresh_token,
      expires_at:    response.expires_at.to_i
    )

    @api_client = nil
  rescue Strava::Errors::Fault => e
    raise AuthError, "Failed to refresh Strava token: #{e.message}"
  end
end

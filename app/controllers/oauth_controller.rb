class OauthController < ApplicationController
  before_action :authenticate_user!

  def connect
    redirect_to strava_auth_url, allow_other_host: true
  end

  def callback
    auth = request.env['omniauth.auth']

    token = current_user.strava_token || current_user.build_strava_token
    token.update!(
      access_token:  auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at:    auth.credentials.expires_at,
      athlete_id:    auth.uid,
      scope:         auth.extra.raw_info.to_s
    )

    redirect_to dashboard_path, notice: "Strava connected successfully!"
  end

  def disconnect
    current_user.strava_token&.destroy
    redirect_to profile_path, notice: "Strava disconnected."
  end

  private

  def strava_auth_url
    client_id     = Rails.application.credentials.strava[:client_id]
    redirect_uri  = auth_strava_callback_url
    scope         = "read,activity:read_all"
    "https://www.strava.com/oauth/authorize?client_id=#{client_id}" \
      "&redirect_uri=#{redirect_uri}&response_type=code&scope=#{scope}"
  end
end
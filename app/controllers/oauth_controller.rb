# frozen_string_literal: true

class OauthController < ApplicationController
  before_action :authenticate_user!

  def connect
    redirect_to oauth_client.authorize_url(
      redirect_uri: auth_strava_callback_url,
      scope: "read,activity:read_all",
      approval_prompt: "auto",
      response_type: "code"
    ), allow_other_host: true
  end

  def callback
    if params[:error].present?
      Rails.logger.warn("Strava OAuth denied: #{params[:error]}")
      return redirect_to profile_path, alert: t("flashes.strava.connect_failed")
    end

    token_response = oauth_client.oauth_token(code: params[:code])

    token = current_user.strava_token || current_user.build_strava_token
    token.update!(
      access_token:  token_response.access_token,
      refresh_token: token_response.refresh_token,
      expires_at:    token_response.expires_at.to_i,
      athlete_id:    token_response.athlete&.id,
      scope:         params[:scope].to_s
    )

    SyncStravaActivitiesJob.perform_later(current_user.id)

    redirect_to profile_path, notice: t("flashes.strava.connected")
  rescue Strava::Errors::Fault => e
    Rails.logger.error("Strava OAuth token exchange failed: #{e.message}")
    redirect_to profile_path, alert: t("flashes.strava.connect_failed")
  end

  def disconnect
    current_user.strava_token&.destroy
    redirect_to profile_path, notice: t("flashes.strava.disconnected")
  end

  private

  def oauth_client
    @oauth_client ||= StravaService.build_oauth_client
  end
end

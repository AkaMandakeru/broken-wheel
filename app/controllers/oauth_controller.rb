# frozen_string_literal: true

class OauthController < ApplicationController
  before_action :authenticate_user!

  def connect
    redirect_to Strava::Connection.authorize_url(redirect_uri: auth_strava_callback_url), allow_other_host: true
  end

  def callback
    if params[:error].present?
      Rails.logger.warn("Strava OAuth denied: #{params[:error]}")
      return redirect_to profile_path, alert: t("flashes.strava.connect_failed")
    end

    Strava::Connection.new(current_user).connect!(code: params[:code], scope: params[:scope])

    redirect_to profile_path, notice: t("flashes.strava.connected")
  rescue Strava::Errors::Fault => e
    Rails.logger.error("Strava OAuth token exchange failed: #{e.message}")
    redirect_to profile_path, alert: t("flashes.strava.connect_failed")
  end

  def disconnect
    Strava::Connection.new(current_user).disconnect!
    redirect_to profile_path, notice: t("flashes.strava.disconnected")
  end
end

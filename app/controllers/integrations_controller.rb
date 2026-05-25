# frozen_string_literal: true

class IntegrationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @strava_connected = current_user.connected_to_strava?
  end
end

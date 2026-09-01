# frozen_string_literal: true

# Records that a user has dismissed the "new season" banner.
class SeasonAnnouncementsController < ApplicationController
  before_action :authenticate_user!

  def dismiss
    season = Season.find_by(id: params[:season_id])
    current_user.dismiss_season_announcement(params[:season_id])

    SeasonAnalytics.track(user: current_user, event: "season_announcement_dismissed", season: season)

    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_back fallback_location: root_path }
    end
  end
end

# frozen_string_literal: true

# Records that a user has dismissed the "new season" banner.
class SeasonAnnouncementsController < ApplicationController
  before_action :authenticate_user!

  def dismiss
    Seasons::Announcement.dismiss!(current_user, params[:season_id])

    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_back fallback_location: root_path }
    end
  end
end

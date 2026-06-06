# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      @challenges_count = Challenge.count
      @active_challenges_count = Challenge.where(status: "active").count
      @events_count = Event.count
      @upcoming_events_count = Event.upcoming.count
      @users_count = User.count
      @recent_challenges = Challenge.order(created_at: :desc).limit(5)
      @upcoming_events = Event.upcoming.by_date.limit(5)
    end
  end
end

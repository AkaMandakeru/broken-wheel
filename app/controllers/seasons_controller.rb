# frozen_string_literal: true

class SeasonsController < ApplicationController
  before_action :authenticate_user!, except: [ :index, :show ]
  before_action :set_season, only: [ :show ]

  def index
    @active_seasons = Season.active.by_recent
    @past_seasons = Season.recent_archive
  end

  # The sections are built by Seasons::Dashboard, which the mobile API's season
  # endpoints share; this only hands them to the views.
  def show
    dashboard = Seasons::Dashboard.new(@season, user: current_user, board: params[:board])
    @participation = dashboard.enroll!
    @unclaimed_completions = dashboard.unclaimed_completions

    assign_challenges(dashboard)
    assign_objectives(dashboard)
    assign_dailies(dashboard)
    assign_rewards(dashboard)
    assign_leaderboard(dashboard)

    @community_goal = dashboard.community_goal
    @activities = dashboard.recent_activities

    track_announcement_click
  end

  private

  # The banner's CTA carries ?from=announcement, so the click is measurable
  # without a redirect hop or a second endpoint. Deliberately no "shown" event:
  # the banner renders on every page, and that would drown the funnel.
  def track_announcement_click
    return unless user_signed_in? && params[:from] == "announcement"

    SeasonAnalytics.track(user: current_user, event: "season_announcement_clicked", season: @season)
  end

  # A season that has aged out is closed, not missing — so this sends the player
  # back to the list with a reason rather than a bare 404.
  def set_season
    @season = Seasons::Dashboard.season_scope(current_user).find_by(id: params[:id])
    return if @season

    redirect_to seasons_path, alert: t("flashes.seasons.archived")
  end

  def assign_challenges(dashboard)
    @season_challenges = dashboard.challenges
    @challenges_by_category = dashboard.challenges_by_category
    @weekly_challenges = dashboard.weekly_challenges
    @my_challenge_progress = dashboard.challenge_progress
  end

  def assign_objectives(dashboard)
    @season_objectives = dashboard.objectives
    @legacy_missions = dashboard.legacy_missions
    @completed_objective_ids = dashboard.completed_objective_ids
    @legacy_completed_count = dashboard.legacy_completed_count
  end

  def assign_dailies(dashboard)
    @daily_assignments = dashboard.daily_assignments
    @daily_progress = dashboard.daily_progress
  end

  def assign_rewards(dashboard)
    @rewards = dashboard.level_rewards
    @rewards_by_level = dashboard.rewards_by_level
    @bonus_rewards = dashboard.bonus_rewards
    @granted_reward_ids = dashboard.granted_reward_ids
  end

  def assign_leaderboard(dashboard)
    @board = dashboard.board
    @leaderboard = dashboard.leaderboard
    @leaderboard_rows = dashboard.leaderboard_rows
    @my_position = dashboard.my_position
  end
end

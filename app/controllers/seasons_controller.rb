# frozen_string_literal: true

class SeasonsController < ApplicationController
  before_action :authenticate_user!, except: [ :index, :show ]
  before_action :set_season, only: [ :show ]

  def index
    @active_seasons = Season.active.by_recent
    @past_seasons = Season.where(status: "ended").by_recent
  end

  def show
    # Lazy auto-enrollment: viewing an active season creates the participation
    # so progress/rank show immediately (starting at zero).
    @participation = if user_signed_in? && @season.active?
      SeasonProgressService.ensure_participation(current_user, @season)
    elsif user_signed_in?
      current_user.season_participations.find_by(season_id: @season.id)
    end

    @season_challenges = @season.season_challenges.includes(:challenge)
    @my_challenge_progress = my_challenge_progress
    @season_objectives = @season.season_objectives
    @completed_objective_ids = @participation&.season_objective_completions&.pluck(:season_objective_id) || []
    @rewards = @season.season_rewards
    @granted_reward_ids = @participation&.granted_reward_ids || []
    @leaderboard = @season.season_participations.by_rank.includes(:user).limit(10)
    @activities = @season.season_activities.recent.includes(:user).limit(15)
  end

  private

  def set_season
    @season = Season.find(params[:id])
  end

  # { challenge_id => participation } for the current user, for the season's challenges.
  def my_challenge_progress
    return {} unless user_signed_in?

    current_user.challenge_participations
                .where(challenge_id: @season_challenges.map(&:challenge_id))
                .index_by(&:challenge_id)
  end
end

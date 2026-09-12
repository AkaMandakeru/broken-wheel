# frozen_string_literal: true

class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
    load_seasons
    load_stats
  end

  def edit
    @user = current_user
  end

  def update
    @user = current_user
    params[:user] ||= {}
    params[:user][:sports] = params[:user][:sports] || []
    if @user.update(profile_params)
      redirect_to profile_path, notice: t("flashes.profiles.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # The profile is a season record now: what the user has run, and the medal
  # each season they entered ended with.
  def load_seasons
    @participations = @user.season_history.to_a
    @medals = @participations.select(&:medal_tier)
    @browsable_season_ids = Season.browsable.pluck(:id).to_set
  end

  def load_stats
    @stats = {
      distance_km: @user.workouts.sum(:distance_km).to_f.round(1),
      week_streak: WorkoutStreak.weeks_for(@user),
      workouts:    @user.workouts.count,
      seasons:     @participations.size,
      medals:      @medals.size
    }
  end

  def profile_params
    params.require(:user).permit(:first_name, :last_name, :title, :nickname, :document, :phone, :blood_type, :address, :avatar, sports: [])
  end
end

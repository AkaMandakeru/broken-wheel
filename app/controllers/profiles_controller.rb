# frozen_string_literal: true

class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
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

  def load_stats
    stats = AchievementChecker.user_stats(@user)
    earned = @user.user_badges.includes(:badge)

    @stats = {
      distance_km:  @user.workouts.sum(:distance_km).to_f.round(1),
      week_streak:  stats[:streak].to_i,
      workouts:     stats[:workout_count].to_i,
      earned_count: earned.size,
      total_badges: Badge.where(badge_type: Badge::CATEGORIES.keys).count,
      points:       earned.sum { |ub| ub.badge.points.to_i }
    }
  end

  def profile_params
    params.require(:user).permit(:first_name, :last_name, :title, :nickname, :document, :phone, :blood_type, :address, :avatar, sports: [])
  end
end

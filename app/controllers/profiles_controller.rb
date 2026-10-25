# frozen_string_literal: true

class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
    profile = Profiles::Stats.new(@user)
    @participations = profile.participations
    @medals = profile.medals
    @browsable_season_ids = profile.browsable_season_ids
    @stats = profile.to_h
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
      render :edit, status: :unprocessable_content
    end
  end

  private

  def profile_params
    params.require(:user).permit(*User::PROFILE_ATTRIBUTES, :avatar, sports: [])
  end
end

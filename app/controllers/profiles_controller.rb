# frozen_string_literal: true

class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
  end

  def update
    @user = current_user
    params[:user] ||= {}
    params[:user][:sports] = params[:user][:sports] || []
    if @user.update(profile_params)
      redirect_to profile_path, notice: "Profile updated successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(:first_name, :last_name, :nickname, :document, :phone, :blood_type, :address, :avatar, sports: [])
  end
end

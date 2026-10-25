# frozen_string_literal: true

class ClubsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_club, only: [ :show, :join, :leave ]

  def index
    @clubs = Club.for_sports(current_user.sports)
  end

  def show
    @membership = Clubs::Membership.new(@club, current_user).current
  end

  def create
    @club = Club.new(club_params)
    if Clubs::Membership.create_with_founder(@club, current_user)
      redirect_to club_path(@club), notice: t("flashes.clubs.created")
    else
      @clubs = Club.all
      render :index, status: :unprocessable_content
    end
  end

  def join
    if Clubs::Membership.new(@club, current_user).join
      redirect_to club_path(@club), notice: t("flashes.clubs.joined")
    else
      redirect_to club_path(@club), alert: t("flashes.clubs.already_member")
    end
  end

  def leave
    if Clubs::Membership.new(@club, current_user).leave
      redirect_to clubs_path, notice: t("flashes.clubs.left")
    else
      redirect_to club_path(@club), alert: t("flashes.clubs.not_member")
    end
  end

  private

  def set_club
    @club = Club.find(params[:id])
  end

  def club_params
    params.require(:club).permit(:name, :description, :sport)
  end
end

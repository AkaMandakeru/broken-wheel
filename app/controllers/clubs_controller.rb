# frozen_string_literal: true

class ClubsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_club, only: [:show, :join, :leave]

  def index
    @clubs = Club.includes(:created_by).order(member_count: :desc)
    sports = Array(current_user.sports).reject(&:blank?)
    @clubs = @clubs.where(sport: sports) if sports.any?
  end

  def show
    @membership = current_user.club_memberships.find_by(club: @club)
  end

  def create
    @club = Club.new(club_params)
    @club.created_by = current_user
    if @club.save
      @club.club_memberships.create!(user: current_user, role: "admin")
      @club.increment!(:member_count)
      redirect_to club_path(@club), notice: "Club created!"
    else
      @clubs = Club.all
      render :index, status: :unprocessable_entity
    end
  end

  def join
    if current_user.club_memberships.exists?(club: @club)
      redirect_to club_path(@club), alert: "You're already a member."
      return
    end
    @club.club_memberships.create!(user: current_user, role: "member")
    @club.increment!(:member_count)
    redirect_to club_path(@club), notice: "Joined club!"
  end

  def leave
    membership = current_user.club_memberships.find_by(club: @club)
    if membership
      membership.destroy!
      @club.decrement!(:member_count)
      redirect_to clubs_path, notice: "Left club."
    else
      redirect_to club_path(@club), alert: "Not a member."
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

# frozen_string_literal: true

class ChallengesController < ApplicationController
  before_action :authenticate_user!, except: [ :index ]
  before_action :set_challenge, only: [ :show, :join, :invite ]

  def index
    @type = params[:type].presence_in(Challenge::CHALLENGE_TYPES)
    @challenges = Challenges::Context.listing(type: @type)
    @active_season = Season.active.by_recent.first
    @season_participation = current_user.season_participations.find_by(season: @active_season) if @active_season && user_signed_in?
    @my_participations = Challenges::Context.participation_index(current_user, @challenges)
  end

  def show
    @season = context.season
    @participation = context.participation
    @participations = context.ranking
  end

  def join
    unless context.join!
      redirect_to challenge_path(@challenge), alert: t("flashes.challenges.already_joined")
      return
    end

    notice = if current_user.connected_to_strava?
      t("flashes.challenges.joined")
    else
      t("flashes.challenges.joined_connect_strava")
    end

    redirect_to challenge_path(@challenge), notice: notice
  end

  def invite
    @participation = context.participation
    redirect_to challenge_path(@challenge), alert: t("flashes.challenges.must_join_first") unless @participation
  end

  private

  def set_challenge
    @challenge = Challenge.find(params[:id])
  end

  def context
    @context ||= Challenges::Context.new(@challenge, user: current_user)
  end
end

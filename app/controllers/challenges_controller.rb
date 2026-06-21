# frozen_string_literal: true

class ChallengesController < ApplicationController
  before_action :authenticate_user!, except: [ :index ]
  before_action :set_challenge, only: [ :show, :join, :invite ]

  def index
    @type = params[:type].presence_in(Challenge::CHALLENGE_TYPES)
    @challenges = Challenge.where(status: "active").of_type(@type).order(starts_at: :desc)
    @active_season = Season.active.by_recent.first
    @season_participation = current_user.season_participations.find_by(season: @active_season) if @active_season && user_signed_in?
  end

  def show
    @participation = current_user.challenge_participations.find_by(challenge_id: @challenge.id)
    @participations = @challenge.challenge_participations.includes(:user).order(progress_value: :desc)
  end

  def join
    if current_user.challenge_participations.exists?(challenge_id: @challenge.id)
      redirect_to challenge_path(@challenge), alert: t("flashes.challenges.already_joined")
      return
    end

    participation = current_user.challenge_participations.create!(challenge: @challenge)

    Analytics.track(user: current_user, event: "challenge_joined", properties: { challenge_id: @challenge.id, challenge_type: @challenge.challenge_type, sport: @challenge.sport })

    window = @challenge.workout_window
    workouts = window ? current_user.workouts.where(workout_date: window) : current_user.workouts.none

    workouts = workouts.where(sport: @challenge.sport) if @challenge.sport.present?
    workouts_to_assign = workouts.where(challenge_participation_id: nil)

    if workouts_to_assign.any?
      workouts_to_assign.update_all(challenge_participation_id: participation.id)
      RecomputeChallengeProgress.new(participation).call
    end

    notice = if current_user.connected_to_strava?
                t("flashes.challenges.joined")
              else
                t("flashes.challenges.joined_connect_strava")
              end

    redirect_to challenge_path(@challenge), notice: notice
  end

  def invite
    @participation = current_user.challenge_participations.find_by(challenge_id: @challenge.id)
    redirect_to challenge_path(@challenge), alert: t("flashes.challenges.must_join_first") unless @participation
  end

  private

  def set_challenge
    @challenge = Challenge.find(params[:id])
  end
end
